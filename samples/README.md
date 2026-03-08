# Samples

このディレクトリには、CLIの動作確認に使う総合サンプルを1つだけ置いています。

- `family-showcase.ftree`: サザエさん家族ベースの総合サンプル
  - 複数世代
  - 兄弟
  - 分岐する家系（ノリスケ・タイ子・イクラ）
- `family-showcase.svg`: `family-showcase.ftree` から生成したSVG例

## 生成コマンド

```bash
bin/family-tree render samples/family-showcase.ftree -o samples/family-showcase.svg
```
