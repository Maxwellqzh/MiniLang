# MiniLang

MiniLang 是一个用 Haskell 实现的迷你语言解释器项目。当前代码已经从单纯的词法/语法分析扩展到完整的解释执行流程，并按功能拆成 `Parsing`、`TypeCheck` 和 `Backend` 三部分：

- `Parsing`：负责把源代码转换成 AST。
- `TypeCheck`：负责在执行前检查 AST 的静态类型。
- `Backend`：负责接收 AST，解释执行并输出结果。

当前完整流程：

```txt
source code -> Lexer -> [Token] -> Parser -> Program AST -> TypeCheck -> Eval -> Output + Env
```

在 `eval-dev` 分支中，原 README 里列出的 Backend TODO 已经补齐了一部分运行时支持，主要包括浮点数、匿名函数、ADT 构造器和表达式级 `match` 的解释执行，并新增了对应测试。

## 快速开始

编译项目：

```bash
cabal build exe:MiniLang
```

运行默认调试示例 `examples/showcase.minilang`：

```bash
cabal run exe:MiniLang
```

运行指定文件，先做类型检查，再输出程序中的 `print` 结果：

```bash
cabal run exe:MiniLang -- examples/showcase.minilang
```

输出 Source、Lexer、Parser、TypeCheck、Eval 和 Final Env：

```bash
cabal run exe:MiniLang -- --debug examples/showcase.minilang
```

只查看 Token：

```bash
cabal run exe:MiniLang -- --tokens examples/showcase.minilang
```

只查看 AST：

```bash
cabal run exe:MiniLang -- --ast examples/adt_match.minilang
```

启动交互式 REPL：

```bash
cabal run exe:MiniLang -- repl
```

REPL 会在多次输入之间持久维护运行时环境和类型环境。输入一段或多段 MiniLang 语句后，用空行提交执行；可用 `:env` 查看当前环境，`:reset` 清空环境，`:q` 或 `:quit` 退出。

运行测试：

```bash
cabal test
```

## 语言特点

MiniLang 当前的语言能力可以概括为：

- 基础表达能力：支持整数、浮点数、布尔值、字符串，以及 `+ - * / < <= > >= == !=` 等基础运算。
- 命令式控制流：支持变量定义、赋值、输出、`if / else` 分支和 `while` 循环。
- 函数式能力：支持具名函数、匿名函数、函数调用、函数作为参数和返回值、高阶函数与闭包。
- 递归能力：具名函数在自身函数体内可见，因此可以直接实现递归调用，例如 `fact(n - 1)`。
- 数据建模能力：支持自定义 ADT 和表达式级模式匹配，例如 `data List { Nil; Cons(head, tail); }` 与 `match value { Pattern -> expr; }`。
- 工程辅助能力：支持 `//` 单行注释，并提供文件运行、调试输出、Token/AST 查看与 REPL 调试入口。

其中浮点数、匿名函数、ADT 和 `match` 已完成 Parser 端设计；在 `eval-dev` 分支中，这些能力也已经补齐了 Backend 端的运行时支持。

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
    Typecheck/
      Type.hs
      Error.hs
      Checker.hs
examples/
  sample.minilang
  showcase.minilang
  higher_order.minilang
  higher_order_lambda.minilang
  float_literals.minilang
  adt_match.minilang
test/
  TestMain.hs
PROJECT_STRUCTURE_CHANGES.md
```

主要模块职责：

- `MiniLang.Parsing.Token`：定义词法单元 `Token`
- `MiniLang.Parsing.Lexer`：把源代码字符串转换成 `[Token]`
- `MiniLang.Parsing.Syntax`：定义 AST，包含 `Program`、`Stmt`、`Expr`、`Pattern`
- `MiniLang.Parsing.Parser`：把源码解析成 `Program`
- `MiniLang.Backend.Value`：定义运行时值 `Value` 和环境 `Env`
- `MiniLang.Backend.Error`：定义解释执行阶段的 `RuntimeError`
- `MiniLang.Backend.Eval`：解释执行 AST，入口是 `runProgram`
- `MiniLang.Typecheck.Type`：定义静态类型和类型环境
- `MiniLang.Typecheck.Error`：定义静态类型检查错误
- `MiniLang.Typecheck.Checker`：在执行前完成类型检查
- `Main.hs`：调试入口，串联 Lexer、Parser、TypeCheck 和 Eval
- `MiniLang.Repl`：交互式 REPL，支持跨输入持久维护运行时环境和类型环境
- `test/TestMain.hs`：自动化测试入口，覆盖本次补齐的 Backend 行为
- `PROJECT_STRUCTURE_CHANGES.md`：记录本次目录结构和工程文件变化

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

### 函数、递归和闭包

具名函数定义：

```txt
fn add(a, b) {
  return a + b;
}
```

函数调用：

```txt
add(1, 2)
```

递归调用：

```txt
fn fact(n) {
  if (n == 0) {
    return 1;
  } else {
    return n * fact(n - 1);
  }
}
```

函数调用 AST 使用 `ECall Expr [Expr]`，被调用对象可以是任意表达式，而不只是函数名。因此语言可以自然表示：

```txt
fn makeAdder(base) {
  fn inner(value) {
    return base + value;
  }
  return inner;
}

let adder = makeAdder(10);
let closureResult = adder(5);
makeAdder(10)(5);
```

高阶函数和匿名函数：

```txt
fn applyTwice(f, x) {
  return f(f(x));
}

fn addOne(n) {
  return n + 1;
}

let result = applyTwice(addOne, 10);
```

匿名函数表达式使用 `fn(params) { ... }`：

```txt
let result = apply(fn(n) {
  return n + 1;
}, 10);
```

函数语义：

- 函数在运行时表示为闭包值，保存参数列表、函数体和定义时环境。
- 具名函数会在闭包环境中自绑定，因此支持递归。
- 匿名函数会按定义位置捕获环境，因此可以作为普通值传递和调用。
- 函数调用时使用“闭包环境 + 参数绑定”构造局部环境。
- 函数没有显式 `return` 时返回 `unit`。
- 顶层 `return` 会返回 `ReturnOutsideFunction`。

### ADT 和表达式级 match

Parser 和 Backend 支持自定义 ADT 声明：

```txt
data List {
  Nil;
  Cons(head, tail);
}
```

也支持表达式级 `match`：

```txt
fn sum(xs) {
  return match xs {
    Nil -> 0;
    Cons(head, tail) -> head + sum(tail);
  };
}
```

语法说明：

- `data TypeName { ... }` 是语句，用来声明一组构造器。
- 构造器可以没有字段，例如 `Nil;`。
- 构造器可以带字段名，例如 `Cons(head, tail);`。
- `match` 是表达式，可以放在 `return`、`let`、`print` 和函数参数等表达式位置。
- 每个分支格式为 `pattern -> expr;`。
- `_` 是通配符模式，匹配任意值但不绑定变量。
- 小写标识符模式会被解析为变量模式，例如 `x`。
- 大写开头标识符模式会被解析为构造器模式，例如 `Nil` 或 `Cons(head, tail)`。
- 当前 Parser MVP 暂不支持嵌套模式和字面量模式。

运行时语义：

- `data` 声明会把构造器注册到当前环境中。
- 零参数构造器会直接成为构造器值，例如 `Nil`。
- 带参数构造器会成为可调用的构造器函数，例如 `Cons(1, Nil)`。
- `match` 会按分支顺序尝试匹配，匹配成功后在分支表达式中绑定字段名。
- 没有任何分支匹配时返回 `MatchFailure`。

## Token 设计

关键字：

- `let`
- `data`
- `match`
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
- `TokFloat Double`
- `TokString String`

运算符：

- `+`
- `-`
- `->`
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
- `_`

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
3. 读取整数、浮点数和字符串
4. 处理字符串转义和十六进制转义
5. 识别单字符和双字符运算符
6. 识别 `->` 作为 match 分支箭头
7. 跳过 `//` 单行注释
8. 在非法字符、非法转义、字符串未闭合等场景返回 `LexError`

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
data ConstructorDef = ConstructorDef String [String]

data Stmt
  = SLet String Expr
  | SData String [ConstructorDef]
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
- `data Name { Constructor(...); }`

### 表达式优先级

表达式按以下优先级解析：

1. `==`、`!=`
2. `<`、`<=`、`>`、`>=`
3. `+`、`-`
4. `*`、`/`
5. 函数调用后缀
6. 整数、浮点数、布尔、字符串、变量、匿名函数、`match`、括号表达式

表达式 AST：

```haskell
data Expr
  = EInt Int
  | EFloat Double
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
  | ELambda [String] [Stmt]
  | EMatch Expr [(Pattern, Expr)]
```

模式 AST：

```haskell
data Pattern
  = PWildcard
  | PVar String
  | PConstructor String [String]
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
- data 构造器声明格式错误
- match 分支格式错误
- pattern 格式错误
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
  | VFloat Double
  | VBool Bool
  | VString String
  | VUnit
  | VFunction [String] [Stmt] Env
  | VConstructor String [Value]
  | VConstructorFunction String Int
```

说明：

- `VInt`、`VFloat`、`VBool`、`VString` 分别表示整数、浮点数、布尔值和字符串。
- `VUnit` 表示没有显式返回值。
- `VFunction` 表示函数闭包，保存参数、函数体和定义时环境。
- `VConstructor` 表示已经构造出来的 ADT 值，例如 `Nil` 或 `Cons(1, Nil)`。
- `VConstructorFunction` 表示 `data` 声明注册出来的带参数构造器。
- 函数值显示为 `<function>`，避免递归打印闭包环境。
- 构造器函数显示为 `<constructor Name>`。
- 普通相等比较不允许比较函数值；整数和浮点数可以进行混合数值运算与比较。

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
  | ConstructorArityMismatch String Int Int
  | UnknownConstructor String
  | NotCallable String
  | MatchFailure
  | InvalidPattern String
  | ReturnOutsideFunction
```

典型场景：

- 读取未定义变量：`UndefinedVariable`
- 对不支持的类型做算术、比较或控制流判断：`TypeMismatch`
- 除以零：`DivisionByZero`
- 函数参数数量不匹配：`ArityMismatch`
- 构造器参数数量不匹配：`ConstructorArityMismatch`
- 调用未知大写构造器：`UnknownConstructor`
- 调用非函数/非构造器函数值：`NotCallable`
- `match` 没有任何分支匹配：`MatchFailure`
- 构造器 pattern 字段数量不合法：`InvalidPattern`
- 顶层使用 `return`：`ReturnOutsideFunction`

### Backend TODO 完成情况

原 README 中列出的 Backend TODO 在 `eval-dev` 分支中的完成情况如下：

- 已支持匿名函数 `ELambda` 的求值和调用。
- 已支持浮点值 `EFloat` 的求值、输出和数值运算。
- 已支持 `data` 声明生成可用构造器。
- 已支持构造器调用生成 ADT 值。
- 已支持 `match` 根据模式选择分支并返回表达式结果。
- 已支持构造器模式字段绑定和 `_` 通配符。
- 已为构造器参数错误、未知构造器、match 无匹配分支等情况返回清晰运行时错误。

仍可继续完善的方向包括：嵌套模式、字面量模式、更完整的错误位置信息和更系统的类型检查。

## TypeCheck 如何实现

TypeCheck 位于 Parser 和 Backend 之间：

```haskell
typecheckProgram :: TypeEnv -> Program -> Either TypeError TypeEnv
```

`TypeEnv` 记录当前作用域里的变量、函数和构造器类型。文件运行时从 `emptyTypeEnv` 开始；REPL 则会把上一轮保存的类型环境传给下一轮，因此多次输入之间可以持续检查类型一致性。

当前实现借鉴了 Hindley-Milner 类型推断中的合一思想，但范围更小：它是一个面向 MiniLang AST 的单态、流敏感类型检查器。支持：

- `Int`、`Float`、`Bool`、`String`、`Unit`
- 函数类型和高阶函数
- `data` 构造器和 `match`
- `let` 的类型推断和赋值语句的类型一致性
- `if` / `while` 条件必须是 `Bool`
- 函数调用参数数量和参数类型检查
- `return` 只能出现在函数体内
- 函数体中所有返回路径的类型统一
- 数值运算和比较的静态约束

### 类型状态与替换表

类型推断过程中需要持续分配新的类型变量，并保存已经推导出的替换关系。实现中使用 `TCState` 显式维护这两部分状态：

```haskell
data TCState = TCState
  { tcNextVar :: Int
  , tcSubst :: Map.Map Int Type
  }
```

- `tcNextVar`：为新的未知类型分配唯一编号，例如 `t0`、`t1`。
- `tcSubst`：记录类型变量的替换关系，例如 `t0 = String`。

`TC` Monad 把“旧状态 -> 推导结果或错误 -> 新状态”的过程封装起来：

```haskell
newtype TC a = TC
  { runTC :: TCState -> Either TypeError (a, TCState)
  }
```

这样，检查 AST 节点时既可以更新替换表，也可以在发现类型错误时立即返回 `Left TypeError`。

### 合一算法

`unifyWith` 用来断言两个类型必须兼容。遇到类型变量时，它会把变量绑定到具体类型；遇到函数类型时，它会递归检查参数和返回值。

例如，期望类型和实际类型分别为：

```txt
Fun [t1]     -> Int
Fun [String] -> t2
```

合一后替换表会增加：

```txt
t1 = String
t2 = Int
```

最终得到统一类型：

```txt
Fun [String] -> Int
```

### 赋值类型安全

赋值语句是类型检查中特别重要的一处。变量已经定义后，新的赋值不能悄悄改变它的类型：

```haskell
SAssign name expr -> do
  expectedType <- lookupType env name
  exprType <- inferExpr env expr
  unifyWith ("assignment to " ++ show name) expectedType exprType
  resolvedType <- resolveType expectedType
  resolvedEnv <- normalizeEnv env
  pure (continueWith (Map.insert name resolvedType resolvedEnv))
```

例如，`x` 已经被推断为 `Int` 后，再赋值为字符串会在执行前被拦截：

![TypeCheck 拒绝非法重赋值](docs/images/typecheck-assignment-error.png)

### 当前边界

当前实现是实用版静态检查器，不是完整的 Hindley-Milner 系统。暂不包含：

- let-polymorphism
- 泛型 ADT
- 模式匹配穷尽性检查
- 嵌套模式和字面量模式
- 类型错误的位置标注
- 独立的数值类型类；两个尚未约束的参数直接参与数值运算时，当前实现会默认推断为 `Int`

实现文件主要是：

- `app/MiniLang/Typecheck/Type.hs`
- `app/MiniLang/Typecheck/Error.hs`
- `app/MiniLang/Typecheck/Checker.hs`

## REPL 如何实现

REPL 入口位于 `MiniLang.Repl`。启动命令：

```bash
cabal run exe:MiniLang -- repl
```

启动后输入 `:help` 可以查看当前支持的命令：

![REPL 启动与帮助命令](docs/images/repl-help.png)

### 双环境状态

REPL 不只是重复调用解释器，还需要在多次输入之间保存状态。实现中使用 `ReplState` 同时维护运行时环境和类型环境：

```haskell
data ReplState = ReplState
  { replRuntimeEnv :: Env
  , replTypeEnv :: TypeEnv
  }
```

- `replRuntimeEnv`：保存实际运行时值，例如变量、函数闭包和构造器。
- `replTypeEnv`：保存对应的静态类型，供下一轮输入继续做类型检查。

每轮循环大致是：

1. 读取输入。空行提交当前块。
2. 调用 `parseProgram` 解析成 AST。
3. 用上一轮保存的 `replTypeEnv` 调 `typecheckProgram`。
4. 类型通过后，用上一轮保存的 `replRuntimeEnv` 调 `runProgramWithEnv`。
5. 只有执行成功时，才提交新的运行时环境和类型环境。
6. 解析失败、类型检查失败或运行时失败时，保留旧状态继续会话。

因此，REPL 可以跨多轮输入保留变量和函数：

![REPL 多行输入与环境持久化](docs/images/repl-persistent-env.png)

截图中的 `base` 在第一轮输入后被保存在环境中；第二轮定义的 `addBase` 闭包可以继续引用它；后续调用 `addBase(5)` 得到 `15`。最后，`:env` 打印出当前环境中的变量和函数。

### 错误容错

REPL 对三类错误分别进行拦截：

- Parse 错误：源码不能构成合法 AST。
- TypeCheck 错误：AST 存在静态类型不匹配。
- Eval 错误：通过静态检查后，执行阶段仍然失败。

任意阶段失败时，REPL 都只打印错误，不提交本轮产生的新环境。下一次循环仍然使用之前保存的状态。这样，一次错误输入不会破坏已经定义好的变量和函数。

### REPL 命令

支持的命令有：

- `:help`：显示帮助。
- `:env`：打印当前运行时环境。
- `:reset`：同时清空运行时环境和类型环境。
- `:q`：退出 REPL。
- `:quit`：退出 REPL。

`:` 命令只在当前输入块为空时识别。源码可以单行输入，也可以多行输入；空行表示提交当前输入块。

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

额外示例：

- `examples/higher_order.minilang`：高阶函数
- `examples/higher_order_lambda.minilang`：匿名函数表达式
- `examples/float_literals.minilang`：浮点数字面量和浮点运算
- `examples/adt_match.minilang`：ADT 和表达式级 match

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

## 测试覆盖

`test/TestMain.hs` 覆盖了本次补齐的主要 Backend 行为：

- 匿名函数求值和调用。
- 浮点输出、浮点运算、整型/浮点混合运算。
- 浮点比较和整型/浮点相等比较。
- ADT 构造器生成运行时值。
- `match` 递归求和。
- `_` 通配符 fallback。
- 构造器参数数量错误。
- 未知构造器错误。
- `match` 无匹配分支错误。

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
- TypeCheck 层负责执行前的静态类型检查。
- Backend 层负责 AST 到执行结果。
- Main 层负责把三部分串起来做调试运行。
- Test 层负责覆盖关键解释执行路径。

后续可以继续补充：

- 更完整的错误位置信息
- 更完整的类型系统，例如 let-polymorphism、泛型 ADT、模式穷尽性检查和错误位置信息
- 嵌套模式和字面量模式
- 更多标准库函数
- 更细粒度的 CLI/REPL 自动化测试
