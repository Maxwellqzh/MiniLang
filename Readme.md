# MiniLang

MiniLang 是一个用 Haskell 实现的迷你语言解释器。当前版本基于 GitHub `main` 分支最新提交：

```txt
333a7a5a69e3adc5be26c49cc1cb420dce99706b
```

本次在该版本基础上补齐了 README 图片中列出的 Backend TODO，并保留 upstream 已经实现的 Parser、示例文件和 REPL。

## 本次实现内容

已完成的 Backend TODO：

- 支持匿名函数 `ELambda` 的求值和调用。
- 支持浮点值 `EFloat` 的求值、输出和数值运算。
- 支持 `data` 声明生成可用构造器。
- 支持构造器调用生成 ADT 值。
- 支持 `match` 根据模式选择分支并返回表达式结果。
- 支持构造器模式字段绑定和 `_` 通配符。
- 为构造器参数错误、未知构造器、`match` 无匹配分支等情况返回清晰运行时错误。

额外工程化补充：

- 新增 `MiniLang-test` 自动化测试套件。
- 命令行入口新增普通运行、调试、Token 输出、AST 输出和 REPL 模式。
- 新增 `PROJECT_STRUCTURE_CHANGES.md` 记录本次目录结构变化。

## 快速开始

构建项目：

```bash
cabal build
```

运行默认调试示例 `examples/showcase.minilang`：

```bash
cabal run MiniLang
```

只运行指定文件并输出程序中的 `print` 结果：

```bash
cabal run MiniLang -- examples/float_literals.minilang
cabal run MiniLang -- examples/adt_match.minilang
```

输出 Source、Lexer、Parser、Eval 和 Final Env：

```bash
cabal run MiniLang -- --debug examples/showcase.minilang
```

只查看 Token：

```bash
cabal run MiniLang -- --tokens examples/showcase.minilang
```

只查看 AST：

```bash
cabal run MiniLang -- --ast examples/adt_match.minilang
```

启动交互式 REPL：

```bash
cabal run MiniLang -- repl
```

运行测试：

```bash
cabal test
```

## 当前语言能力

MiniLang 当前支持：

- 整数、浮点数、布尔值、字符串。
- 基础运算：`+ - * / < <= > >= == !=`。
- 变量定义与赋值：`let x = expr;`、`x = expr;`。
- 输出语句：`print expr;`。
- 流程控制：`if / else`、`while`。
- 函数定义与调用：`fn name(...) { ... }`、`name(...)`。
- 匿名函数表达式：`fn(x) { return x + 1; }`。
- 递归函数、闭包和高阶函数。
- 自定义 ADT：`data List { Nil; Cons(head, tail); }`。
- 表达式级模式匹配：`match value { Pattern -> expr; }`。
- 单行注释：`// comment`。
- 交互式 REPL。

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
  higher_order.minilang
  higher_order_lambda.minilang
  float_literals.minilang
  adt_match.minilang
test/
  TestMain.hs
PROJECT_STRUCTURE_CHANGES.md
```

## Backend 运行时值

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

- `VFunction` 表示函数闭包。
- `VConstructor` 表示已经构造出来的 ADT 值。
- `VConstructorFunction` 表示 `data` 声明注册出来的带参数构造器。
- `VFloat` 参与数值运算时支持和 `VInt` 混合运算，结果为浮点值。

## 运行时错误

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

- 构造器参数数量错误：`ConstructorArityMismatch`
- 调用未知大写构造器：`UnknownConstructor`
- `match` 没有任何分支匹配：`MatchFailure`
- 构造器 pattern 字段数量不合法：`InvalidPattern`
- 函数参数数量错误：`ArityMismatch`
- 调用非函数/非构造器函数值：`NotCallable`

## 示例

匿名函数：

```txt
fn apply(f, x) {
  return f(x);
}

print apply(fn(n) {
  return n + 1;
}, 10);
```

浮点运算：

```txt
let pi = 3.14;
let radius = 2.0;
let area = pi * radius * radius;
print area;
```

ADT 和 match：

```txt
data List {
  Nil;
  Cons(head, tail);
}

fn sum(xs) {
  return match xs {
    Nil -> 0;
    Cons(head, tail) -> head + sum(tail);
  };
}
```

## 测试覆盖

`test/TestMain.hs` 覆盖：

- 匿名函数求值和调用。
- 浮点输出、浮点运算、整型/浮点混合运算。
- 浮点比较和整型/浮点相等比较。
- ADT 构造器生成运行时值。
- `match` 递归求和。
- `_` 通配符 fallback。
- 构造器参数数量错误。
- 未知构造器错误。
- match 无匹配分支错误。

## 后续方向

可以继续扩展：

- 更完整的错误位置信息。
- 静态类型检查。
- 嵌套模式和字面量模式。
- 更多标准库函数。
- 更细粒度的 CLI/REPL 自动化测试。
