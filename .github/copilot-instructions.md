# プロジェクトガイドライン（共通）

## 前提

- **回答は必ず日本語で行うこと。**
- コードの変更をする際、変更量が200行を超える可能性が高い場合は、事前に「この指示では変更量が200行を超える可能性がありますが、実行しますか？」とユーザーに確認をとること。
- 何か大きい変更を加える場合、まず何をするのか計画を立てた上で、ユーザーに「このような計画で進めようと思います。」と提案すること。
- 考えてから書くこと
- シンプル優先
- 必要な部分だけ触ること
- ゴール基準で動くこと


## コーディング規約

Swift のコーディング規約については `.github/skills/swift-coding-standards/SKILL.md` を参照すること。

## UI 設計原則
- Apple共通ガイドライン（`.github/instructions/apple.instructions.md`）を遵守すること。
- macOS 向けの変更では `.github/instructions/macos.instructions.md` を、iOS 向けの変更では `.github/instructions/ios.instructions.md` を参照すること。

## Custom Agent 運用

- custom agent は役割で使い分ける。要件整理は `product-manager`、技術設計は `architect`、実装は `developer`、UI/UX は `ui-designer`、レビューは `reviewer`、検証は `tester`、複数委譲の統合は `orchestrator` を優先する。
- custom agent に handoff する際は、この `.github/copilot-instructions.md` と`.github/instructions/apple.instructions.md`を共通前提として渡す。
- macOS 変更は `.github/instructions/macos.instructions.md`、iOS 変更は `.github/instructions/ios.instructions.md` を追加前提として渡す。
- Swift コードの規約判断では `.github/skills/swift-coding-standards/SKILL.md` を参照させる。
- UI 変更では Apple HIG、Liquid Glass、アクセシビリティ、Dynamic Type、Safe Area の遵守を handoff に明記する。
- `NightScope/` と `NightScopeTests/` は macOS 文脈、`NightScopeiOS/` は iPhone 向け iOS 文脈として扱う。
- 実装・レビュー・テストで完了条件を置く場合は、原則として README 記載の `xcodebuild` コマンドを基準にする。
- 重要な設計変更や複数ターゲット変更では、`developer` だけで閉じず `reviewer` と `tester` を品質ゲートに含める。