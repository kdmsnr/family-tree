# family-tree

GEDCOM と簡易テキスト記法をサポートして家系図を SVG に出力する Ruby CLI です。

## 必要環境

- Ruby 3.4 以上

## 使い方

```bash
bin/family-tree render INPUT -o OUTPUT.svg
```

厳格モード（未対応タグがあると失敗）:

```bash
bin/family-tree render INPUT -o OUTPUT.svg --strict
```

入力形式を明示したい場合:

```bash
bin/family-tree render INPUT -o OUTPUT.svg --format gedcom
bin/family-tree render INPUT -o OUTPUT.svg --format simple
```

## v1 で対応する GEDCOM タグ

- レコード: `INDI`, `FAM`
- 個人情報: `NAME`, `SEX`, `BIRT`, `DEAT`, `DATE`
- 画像: `OBJE`, `FILE`（`INDI`レコード内の最小サポート）
- 家族情報: `HUSB`, `WIFE`, `CHIL`

## 簡易テキスト記法（推奨: 手書き入力）

```text
person p1 name="Taro Yamada" sex=M birth=1970 image=images/taro.png
person p2 name="Hanako Suzuki" sex=F birth=1973
person p3 name="Ichiro Yamada" sex=M birth=2000
family f1 husband=p1 wife=p2 children=p3
```

- `person <id> key=value ...`
  - 対応キー: `name`, `sex`, `birth|born`, `death|died`, `image|avatar|photo`
- `family <id> key=value ...`
  - 対応キー: `husband`, `wife`, `children|kids`, `spouses`
  - `spouses` は `spouses=p1,p2` の形式

## v1 の制約

- 文字コードは UTF-8 前提（ANSEL などは非対応）
- 未対応タグは警告して無視（`--strict` 時はエラー）
- 養子・離婚・高度な拡張タグは未対応
- SVGは静的出力（インタラクティブ機能なし）

## テスト実行

```bash
ruby -Ilib:test test/run_all.rb
```

## サンプル

- サンプル入力/出力: `samples/`
- 例:

```bash
bin/family-tree render samples/family-showcase.ftree -o samples/family-showcase.svg
```
