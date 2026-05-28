# MiniLang

MiniLang 是一个用 Haskell 实现的迷你语言解释器项目。当前代码已经从单纯的词法/语法分析扩展到完整的解释执行流程，并按功能拆成 `Parsing` 和 `Backend` 两部分：

- `Parsing`：负责把源代码转换成 AST。
- `Backend`：负责接收 AST，解释执行并输出结果。

当前完整流程：

```txt
source code -> Lexer -> [Token] -> Parser -> Program AST -> Eval -> Output + Env
```

## 语言特点

MiniLang 当前支持：

- 基础运算：`+ - * / < <= > >= == !=`
- 布尔、整数、字符串字面量
- 变量定义与赋值：`let x = expr;`、`x = expr;`
- 输出语句：`print expr;`
- 流程控制：`if / else`、`while`
- 函数定义与调用：`fn name(...) { ... }`、`name(...)`
- `return` 从函数体中返回值
- 递归函数，例如 `fact(n - 1)`
- 闭包式函数返回和二次调用，例如 `makeAdder(10)(5)` 或先保存为变量再调用
- 单行注释：`// comment`

## 项目结构

```txt
app/
  Main.hs
  MiniLang/
    Repl.hs
    Parsing/
      Token.hs
      Lexer.hs
      Syntax.hs
      Parser.hs
    Backend/
      Value.hs
      Error.hs
      Eval.hs
examples/
  sample.minilang
  showcase.minilang
```

主要模块职责：

- `MiniLang.Parsing.Token`：定义词法单元 `Token`
- `MiniLang.Parsing.Lexer`：把源代码字符串转换成 `[Token]`
- `MiniLang.Parsing.Syntax`：定义 AST，包含 `Program`、`Stmt`、`Expr`
- `MiniLang.Parsing.Parser`：把源码解析成 `Program`
- `MiniLang.Backend.Value`：定义运行时值 `Value` 和环境 `Env`
- `MiniLang.Backend.Error`：定义解释执行阶段的 `RuntimeError`
- `MiniLang.Backend.Eval`：解释执行 AST，入口是 `runProgram`
- `Main.hs`：调试入口，串联 Lexer、Parser 和 Eval
- `MiniLang.Repl`：REPL 占位模块，当前尚未实现交互式执行

## 语言设定

### 基础语句

```txt
let x = expr;
x = expr;
print expr;
if (expr) { ... } else { ... }
while (expr) { ... }
```

语义说明：

- `let x = expr;` 会把表达式结果绑定到当前环境，允许覆盖同名变量。
- `x = expr;` 要求变量已经存在，否则返回 `UndefinedVariable`。
- `print expr;` 会把值转换成文本并追加到输出列表。
- `if` 和 `while` 的条件必须是布尔值。
- `if` 和 `while` 不创建新的块级作用域，因此分支和循环里的赋值会更新当前环境。

### 函数语句

函数定义：

```txt
fn add(a, b) {
  return a + b;
}
```

函数调用：

```txt
add(1, 2)
```

函数语义：

- 函数在运行时表示为闭包值，保存参数列表、函数体和定义时环境。
- 具名函数会在闭包环境中自绑定，因此支持递归。
- 函数调用时使用“闭包环境 + 参数绑定”构造局部环境。
- 参数绑定会覆盖闭包环境中的同名变量。
- 函数内部赋值只影响本次调用的局部环境，不回写调用者环境。
- 函数没有显式 `return` 时返回 `unit`。
- 顶层 `return` 会返回 `ReturnOutsideFunction`。

### 递归支持

MiniLang 支持具名函数递归。例如：

```txt
fn fact(n) {
  if (n == 0) {
    return 1;
  } else {
    return n * fact(n - 1);
  }
}
```

Parser 会把 `fact(n - 1)` 解析成普通调用表达式：

```haskell
ECall (EVar "fact") [ESub (EVar "n") (EInt 1)]
```

真正让函数名在函数体内可见的是 Backend 中 `SFun` 的运行时自绑定逻辑。

### 闭包友好的调用设计

函数调用 AST 使用：

```haskell
ECall Expr [Expr]
```

而不是：

```haskell
ECall String [Expr]
```

这意味着被调用对象可以是任意表达式，而不只是函数名。因此语言可以自然表示：

```txt
f(1)
outer(10)(20)
(getFunc())(3)
```

当前示例中使用了闭包式函数返回：

```txt
fn makeAdder(base) {
  fn inner(value) {
    return base + value;
  }
  return inner;
}

let adder = makeAdder(10);
let closureResult = adder(5);
```

最终 `closureResult` 的值为 `15`。

## Token 设计

关键字：

- `let`
- `fn`
- `return`
- `if`
- `else`
- `while`
- `print`
- `true`
- `false`

标识符和字面量：

- `TokIdent String`
- `TokInt Int`
- `TokString String`

运算符：

- `+`
- `-`
- `*`
- `/`
- `=`
- `==`
- `!=`
- `<`
- `>`
- `<=`
- `>=`

分隔符：

- `(`
- `)`
- `{`
- `}`
- `;`
- `,`

## Lexer 如何实现

`Lexer` 的目标是把源代码字符串转换成 `Token` 列表：

```haskell
lexProgram :: String -> Either LexError [Token]
```

成功时返回：

```haskell
Right [Token]
```

失败时返回：

```haskell
Left LexError
```

`lexProgram` 内部通过递归函数扫描输入，同时维护行号和列号：

```haskell
go :: Int -> Int -> String -> Either LexError [Token]
```

Lexer 负责：

1. 跳过空格、换行和 tab
2. 识别标识符和关键字
3. 读取整数和字符串
4. 处理字符串转义和十六进制转义
5. 识别单字符和双字符运算符
6. 跳过 `//` 单行注释
7. 在非法字符、非法转义、字符串未闭合等场景返回 `LexError`

## Parser 如何实现

`Parser` 的目标是把源码解析成 AST：

```haskell
parseProgram :: String -> Either ParseError Program
```

内部流程：

```txt
source -> lexProgram -> [Token] -> parseTokens -> Program
```

Parser 使用递归下降方式。每个解析函数通常返回两个结果：

- 当前解析出的 AST 节点
- 尚未消费的 token

例如：

```haskell
parseExpr :: [Token] -> Either ParseError (Expr, [Token])
```

### 程序和语句列表

整个程序是语句列表：

```haskell
newtype Program = Program [Stmt]
```

`parseStmtList` 会持续读取语句，直到 token 用完，或遇到右花括号 `TokRBrace`。

### 单条语句解析

当前支持的语句 AST：

```haskell
data Stmt
  = SLet String Expr
  | SFun String [String] [Stmt]
  | SReturn Expr
  | SAssign String Expr
  | SPrint Expr
  | SIf Expr [Stmt] [Stmt]
  | SWhile Expr [Stmt]
```

对应语法包括：

- `let x = expr;`
- `x = expr;`
- `print expr;`
- `if (expr) { ... } else { ... }`
- `while (expr) { ... }`
- `fn name(params) { ... }`
- `return expr;`

### 表达式优先级

表达式按以下优先级解析：

1. `==`、`!=`
2. `<`、`<=`、`>`、`>=`
3. `+`、`-`
4. `*`、`/`
5. 函数调用后缀
6. 整数、布尔、字符串、变量、括号表达式

表达式 AST：

```haskell
data Expr
  = EInt Int
  | EBool Bool
  | EString String
  | EVar String
  | EAdd Expr Expr
  | ESub Expr Expr
  | EMul Expr Expr
  | EDiv Expr Expr
  | ELt Expr Expr
  | ELe Expr Expr
  | EGt Expr Expr
  | EGe Expr Expr
  | EEq Expr Expr
  | ENeq Expr Expr
  | ECall Expr [Expr]
```

### Parser 错误处理

Parser 会检测：

- 语句不完整
- 表达式不完整
- 缺少分号
- 缺少右括号
- 缺少右花括号
- 参数列表格式错误
- 实参列表格式错误
- 尾部存在未消费 token

## Backend 如何实现

Backend 的核心入口：

```haskell
runProgram :: Program -> Either RuntimeError (Output, Env)
```

也就是说，Backend 的输入是 Parser 产生的 AST，输出是：

- `Output`：程序中所有 `print` 产生的文本列表
- `Env`：程序结束后的最终运行时环境
- `RuntimeError`：解释执行阶段发生的错误

### 运行时值

```haskell
type Env = Map.Map String Value

data Value
  = VInt Int
  | VBool Bool
  | VString String
  | VUnit
  | VFunction [String] [Stmt] Env
```

说明：

- `VInt`、`VBool`、`VString` 分别表示整数、布尔值和字符串。
- `VUnit` 表示没有显式返回值。
- `VFunction` 表示函数闭包，保存参数、函数体和定义时环境。
- 函数值显示为 `<function>`，避免递归打印闭包环境。
- 普通相等比较不允许比较函数值。

### 执行控制流

Backend 内部使用执行信号区分普通执行和函数返回：

```haskell
data ExecSignal
  = Continue
  | Returned Value
```

`return` 不是普通值绑定，而是控制流信号。这个信号会从嵌套的 `if`、`while` 和语句块中向外传播，直到函数调用边界被消费。

### 运行时错误

当前运行时错误包括：

```haskell
data RuntimeError
  = UndefinedVariable String
  | TypeMismatch String
  | DivisionByZero
  | ArityMismatch Int Int
  | NotCallable String
  | ReturnOutsideFunction
```

典型场景：

- 读取未定义变量：`UndefinedVariable`
- 对非整数做算术：`TypeMismatch`
- 除以零：`DivisionByZero`
- 函数参数数量不匹配：`ArityMismatch`
- 调用非函数值：`NotCallable`
- 顶层使用 `return`：`ReturnOutsideFunction`

## 示例输入

综合示例文件位于：

```txt
examples/showcase.minilang
```

示例覆盖：

- 变量声明和算术
- 布尔值和字符串转义
- 函数定义和调用
- 递归 factorial
- 闭包式 `makeAdder`
- 比较和相等运算
- `while` 循环
- `if / else` 控制流

节选：

```txt
fn fact(n) {
  if (n == 0) {
    return 1;
  } else {
    return n * fact(n - 1);
  }
}

fn makeAdder(base) {
  fn inner(value) {
    return base + value;
  }
  return inner;
}

let adder = makeAdder(10);
let closureResult = adder(5);
let factorial = fact(5);
```

运行后，最终环境中会包含：

```txt
closureResult = 15
factorial = 120
```

## 运行方式

构建项目：

```bash
cabal build
```

运行调试入口：

```bash
cabal run MiniLang
```

当前 `main` 会：

- 读取 `examples/showcase.minilang`
- 打印源代码
- 打印 Lexer 输出
- 打印 Parser 输出
- 执行 AST
- 打印 Eval 输出
- 打印最终环境

## 调试 Backend

可以在 GHCi 中直接构造 AST 并传给 `runProgram`：

```haskell
import MiniLang.Parsing.Syntax
import MiniLang.Backend.Eval

runProgram (Program [SLet "x" (EInt 1), SPrint (EVar "x")])
```

预期返回：

```haskell
Right (["1"], fromList [("x",1)])
```

也可以测试错误路径：

```haskell
runProgram (Program [SPrint (EVar "missing")])
```

预期返回：

```haskell
Left (UndefinedVariable "missing")
```

## 当前状态和后续方向

当前项目已经形成清晰的前后端结构：

- Parsing 层负责源码到 AST。
- Backend 层负责 AST 到执行结果。
- Main 层负责把两部分串起来做调试运行。

后续可以继续补充：

- 交互式 REPL
- 文件路径参数，而不是在 `Main.hs` 中固定读取 showcase
- 自动化测试框架
- 更完整的类型系统和错误位置信息
