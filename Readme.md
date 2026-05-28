# MiniLang

MiniLang 是一个用 Haskell 实现的迷你语言解释器项目。当前代码按 `Parsing` 和 `Backend` 两部分组织：前者负责把源代码解析成 AST，后者负责解释执行 AST。

当前流程：

```txt
source code -> Lexer -> [Token] -> Parser -> Program -> Eval -> Output + Env
```

## 语言特点

MiniLang 设计上具有以下特点：

- 支持基础运算：`+ - * / < <= > >= == !=`
- 支持流程控制：`if / else`、`while`
- 支持函数声明与调用：`fn name(...) { ... }`、`call(...)`
- 支持递归：语法上允许函数在函数体内引用自身
- 支持闭包友好的调用结构：函数调用 AST 使用 `ECall Expr [Expr]`
- 支持单行注释：`// comment`

## 项目结构

- `app/MiniLang/Parsing/Token.hs`：词法单元定义
- `app/MiniLang/Parsing/Lexer.hs`：词法分析器
- `app/MiniLang/Parsing/Syntax.hs`：抽象语法树定义
- `app/MiniLang/Parsing/Parser.hs`：语法分析器
- `app/MiniLang/Backend/Value.hs`：运行时值和环境定义
- `app/MiniLang/Backend/Error.hs`：运行时错误定义
- `app/MiniLang/Backend/Eval.hs`：解释执行
- `app/Main.hs`：调试入口，会打印 Lexer、Parser 和 Eval 结果
- `examples/sample.minilang`：示例输入文件

## 语言设定

### 基础语句

- 变量定义：`let x = expr;`
- 变量赋值：`x = expr;`
- 输出语句：`print expr;`
- 条件语句：`if (expr) { ... } else { ... }`
- 循环语句：`while (expr) { ... }`

### 函数语句

- 函数定义：

```txt
fn add(a, b) {
  return a + b;
}
```

- 函数调用：

```txt
add(1, 2)
```

### 递归支持设定

MiniLang 允许具名函数在自身函数体中引用自己，因此语法上支持递归。例如：

```txt
fn fact(n) {
  if (n == 0) {
    return 1;
  } else {
    return n * fact(n - 1);
  }
}
```

Parser 会把这里的 `fact(n - 1)` 解析成普通调用表达式。  
真正让“函数名在自身函数体内可见”的规则，需要由 `Eval` 在运行时环境里实现。

### 闭包友好的调用设计

为了方便后续实现闭包和高阶函数，函数调用的 AST 采用：

```haskell
ECall Expr [Expr]
```

而不是：

```haskell
ECall String [Expr]
```

这意味着被调用对象不再只能是函数名，而可以是任意表达式。这样后续就能自然支持：

```txt
f(1)
outer(10)(20)
(getFunc())(3)
```

这对闭包实现非常重要，因为闭包常常要把函数作为值返回后再调用。

### 字面量与表达式

- 整数
- 布尔值：`true`、`false`
- 字符串
- 变量引用
- 函数调用
- 括号表达式
- 运算：`+ - * / < <= > >= == !=`

### 注释

当前语言支持单行注释：

```txt
// this is a comment
let x = 1;
```

Lexer 会直接跳过 `//` 到该行结尾之间的内容，不会生成任何 token。

## Token 设计

### 关键字

- `let`
- `fn`
- `return`
- `if`
- `else`
- `while`
- `print`
- `true`
- `false`

### 标识符和字面量

- `TokIdent String`
- `TokInt Int`
- `TokString String`

### 运算符

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

### 分隔符

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

词法分析失败时返回：

```haskell
Left LexError
```

成功时返回：

```haskell
Right [Token]
```

### 核心思路

`lexProgram` 内部通过递归函数 `go` 扫描输入：

```haskell
go :: Int -> Int -> String -> Either LexError [Token]
```

三个参数分别是：

- 当前行号
- 当前列号
- 当前未处理输入

每次只处理当前字符，然后递归处理剩余内容。

### Lexer 负责的主要工作

1. 跳过空格、换行和 tab，并维护行列号
2. 用 `span` 读取标识符和关键字
3. 读取整数并构造 `TokInt`
4. 识别单字符符号，如 `+`、`(`、`;`
5. 识别双字符运算符，如 `==`、`<=`、`>=`
6. 处理 `!=`
7. 处理字符串和转义字符
8. 识别函数新增关键字 `fn`、`return`
9. 识别参数分隔符 `,`
10. 跳过 `//` 单行注释

### 和闭包友好调用相关的 Lexer 说明

把 `ECall` 从 `String` 升级为 `Expr` 之后，Lexer 本身不需要新增 token。  
也就是说，闭包友好的调用能力主要来自 AST 和 Parser 的升级，词法层仍然沿用这些 token：

- `TokIdent`
- `TokLParen`
- `TokRParen`
- `TokComma`

### Lexer 错误处理

当前 `Lexer` 会检测：

- 非法字符
- 单独出现的 `!`
- 字符串未闭合
- 字符串中直接换行
- 非法转义
- 非法十六进制转义

## Parser 如何实现

`Parser` 的目标是把 `[Token]` 转成 AST：

```haskell
parseProgram :: String -> Either ParseError Program
```

内部流程是：

1. 先调用 `lexProgram`
2. 成功后把 `[Token]` 交给真正的语法分析函数

```txt
source -> lexProgram -> [Token] -> parseTokens -> Program
```

### 递归下降解析

Parser 采用递归下降写法。每个解析函数都返回两部分：

- 当前解析出的 AST 节点
- 还没消费完的 token

例如：

```haskell
parseExpr :: [Token] -> Either ParseError (Expr, [Token])
```

### 程序和语句列表

整个程序是语句列表：

```haskell
Program [Stmt]
```

`parseTokens` 负责把完整 token 序列解析成 `Program`。  
`parseStmtList` 持续读取语句，直到：

- token 用完
- 或遇到 `TokRBrace`

### 单条语句解析

`parseStmt` 当前支持：

- `let x = expr;`
- `x = expr;`
- `print expr;`
- `if (expr) { ... } else { ... }`
- `while (expr) { ... }`
- `fn name(params) { ... }`
- `return expr;`

### 函数定义如何解析

例如：

```txt
fn add(a, b) {
  return a + b;
}
```

Parser 的处理顺序是：

1. 读到 `TokFn`
2. 读取函数名
3. 读取参数列表 `(...)`
4. 读取函数体 block
5. 构造：

```haskell
SFun "add" ["a", "b"] [...]
```

参数列表由 `parseParamList` 负责，支持：

- 空参数列表：`fn hello() { ... }`
- 多参数列表：`fn add(a, b, c) { ... }`

### return 如何解析

例如：

```txt
return a + b;
```

会被解析成：

```haskell
SReturn (EAdd (EVar "a") (EVar "b"))
```

### 表达式优先级

当前表达式按下面顺序解析：

1. `parseEquality`：`==`、`!=`
2. `parseComparison`：`<`、`<=`、`>`、`>=`
3. `parseAdditive`：`+`、`-`
4. `parseMultiplicative`：`*`、`/`
5. `parsePostfix`：处理函数调用后缀
6. `parsePrimary`：整数、布尔、字符串、变量、括号表达式

### 调用表达式如何升级

现在 parser 使用“原子表达式 + 后缀调用”的形式：

1. `parsePrimary` 先解析出一个基础表达式
2. `parsePostfix` 再检查它后面是否跟着 `(...)`
3. 如果有，就构造 `ECall expr args`
4. 然后继续向后看，允许连续调用

因此现在不仅支持：

```txt
add(x, 8)
```

也支持：

```txt
outer(10)(20)
(f)(x)
```

对应 AST 会类似：

```haskell
ECall (ECall (EVar "outer") [EInt 10]) [EInt 20]
```

### 递归在 Parser 中的体现

从 parser 角度看，递归并不需要新的特殊语句。  
例如：

```txt
fn fact(n) {
  return fact(n - 1);
}
```

这里函数体里的 `fact(n - 1)` 会被正常解析成：

```haskell
ECall (EVar "fact") [...]
```

因此递归语法本身已经成立，真正的“自绑定”规则交给 `Eval` 处理。

### 实参列表如何解析

实参列表由 `parseArgumentList` 负责，支持：

- 空实参：`hello()`
- 多实参：`add(1, 2, 3)`

### Parser 错误处理

当前 parser 会检测：

- 语句不完整
- 表达式不完整
- 缺少分号
- 缺少右括号
- 缺少右花括号
- 参数列表格式错误
- 实参列表格式错误
- 尾部存在未消费 token

## 当前 AST 结构

### Program

```haskell
newtype Program = Program [Stmt]
```

### 语句类型

- `SLet String Expr`
- `SFun String [String] [Stmt]`
- `SReturn Expr`
- `SAssign String Expr`
- `SPrint Expr`
- `SIf Expr [Stmt] [Stmt]`
- `SWhile Expr [Stmt]`

### 表达式类型

- `EInt`
- `EBool`
- `EString`
- `EVar`
- `EAdd`
- `ESub`
- `EMul`
- `EDiv`
- `ELt`
- `ELe`
- `EGt`
- `EGe`
- `EEq`
- `ENeq`
- `ECall Expr [Expr]`

## 示例输入

综合示例文件位于：

```txt
examples/showcase.minilang
```

内容如下：

```txt
// Variable declarations and basic arithmetic
let x = 42;
let msg = "hello\nworld";
fn add(a, b) {
  return a + b;
}

let total = add(x, 8);
print msg;
print total;

if (x >= 10) {
  x = x + 1;
  print "x updated";
} else {
  print "x too small";
}
```

## 示例 Parser 输出

这段程序会被解析成类似下面的 AST：

```haskell
Right
  ( Program
      [ SLet "x" (EInt 42)
      , SLet "msg" (EString "hello\nworld")
      , SFun "add" ["a", "b"]
          [ SReturn (EAdd (EVar "a") (EVar "b")) ]
      , SLet "total" (ECall (EVar "add") [EVar "x", EInt 8])
      , SPrint (EVar "msg")
      , SPrint (EVar "total")
      , SIf
          (EGe (EVar "x") (EInt 10))
          [ SAssign "x" (EAdd (EVar "x") (EInt 1))
          , SPrint (EString "x updated")
          ]
          [ SPrint (EString "x too small") ]
      ]
  )
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
- 打印 Eval 输出和最终环境

## 下一步

现在 `Parsing` 目录负责词法、语法和 AST，`Backend` 目录负责运行时值、错误和解释执行。`Main` 仍作为调试入口串联完整流程。
