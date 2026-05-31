# Project Structure Changes

本文档记录本次在最新 GitHub `main` 副本上进行扩展后，对目录结构和文件的影响。

## 目标目录

本次修改基于新克隆目录：

```txt
D:\MiniLang-main-backend-todo-20260531
```

克隆来源：

```txt
https://github.com/Maxwellqzh/MiniLang
main: 333a7a5a69e3adc5be26c49cc1cb420dce99706b
```

## 保持不变的结构

项目主体仍保持原有结构：

```txt
app/
  Main.hs
  MiniLang/
    Repl.hs
    Parsing/
    Backend/
examples/
MiniLang.cabal
Readme.md
```

`Parsing`、`Backend`、`Repl` 目录没有移动，也没有拆分为新的源码层。

## 修改的已有文件

```txt
MiniLang.cabal
Readme.md
app/Main.hs
app/MiniLang/Backend/Value.hs
app/MiniLang/Backend/Error.hs
app/MiniLang/Backend/Eval.hs
```

修改原因：

- `Backend` 文件用于补齐图片中列出的 Backend TODO，包括 `ELambda`、`EFloat`、ADT 构造器、`match` 和运行时错误。
- `Main.hs` 用于在保留 REPL 的同时增加 `--debug`、`--tokens`、`--ast` 等 CLI 模式。
- `MiniLang.cabal` 用于增加测试套件。
- `Readme.md` 用于同步当前已实现能力、运行方式和测试说明。

## 新增文件

```txt
test/TestMain.hs
PROJECT_STRUCTURE_CHANGES.md
```

新增原因：

- `test/TestMain.hs`：提供自动化测试入口，覆盖本次补齐的 Backend 行为。
- `PROJECT_STRUCTURE_CHANGES.md`：记录本次目录和文件结构变化。

## 已存在但本次未新建的示例文件

最新 GitHub `main` 已经包含以下示例文件，本次只验证其可执行性：

```txt
examples/higher_order_lambda.minilang
examples/float_literals.minilang
examples/adt_match.minilang
examples/higher_order.minilang
```

## 删除文件

无。

本次没有删除任何已有源码、示例或文档文件。`app/MiniLang/Repl.hs` 保持最新 `main` 中已经实现的 REPL 功能。
