# Samples

このディレクトリには、CLIの動作確認に使うサンプルを置いています。

- `family-showcase.ftree`: サザエさん家族ベースの総合サンプル
  - 複数世代
  - 兄弟
  - 分岐する家系（ノリスケ・タイ子・イクラ）
  - `image=` によるノード画像表示
- `family-showcase.svg`: `family-showcase.ftree` から生成したSVG例
- `jojo-showcase.ftree`: ジョジョ家系ベースの総合サンプル
  - 複数世代
  - 分岐家系
  - 並行する子孫ライン
- `jojo-showcase.svg`: `jojo-showcase.ftree` から生成したSVG例
- `got-showcase.ftree`: Game of Thronesベースの総合サンプル
  - 複数世代
  - 複数家系（Targaryen / Stark / Lannister / Baratheon / Tully）
  - 再婚・秘密関係・婚外子を含む分岐
- `got-showcase.svg`: `got-showcase.ftree` から生成したSVG例
- `dragonball-showcase.ftree`: ドラゴンボール家系ベースの総合サンプル
  - 複数世代
  - 兄弟順（Raditz→Goku / Gohan→Goten / Trunks→Bulla）
  - 孫家とブルマ家の接続
- `dragonball-showcase.svg`: `dragonball-showcase.ftree` から生成したSVG例
- `targaryen-three-eras.ftree`: ターガリエン家の3作品統合サンプル
  - House of the Dragon
  - A Knight of the Seven Kingdoms
  - Game of Thrones
- `targaryen-three-eras.svg`: `targaryen-three-eras.ftree` から生成したSVG例

## 生成コマンド

```bash
bin/family-tree render samples/family-showcase.ftree -o samples/family-showcase.svg
```

```bash
bin/family-tree render samples/jojo-showcase.ftree -o samples/jojo-showcase.svg
```

```bash
bin/family-tree render samples/got-showcase.ftree -o samples/got-showcase.svg
```

```bash
bin/family-tree render samples/dragonball-showcase.ftree -o samples/dragonball-showcase.svg
```

```bash
bin/family-tree render samples/targaryen-three-eras.ftree -o samples/targaryen-three-eras.svg
```
