# ☕ mug.nvim

mug(mixed utilities for git)は、neovim 上で git を操作するためのコマンド集です。  
いくつかの他作者様が作成された vim plugin の機能を内包します。

## 動作条件

- Neovim >= 0.9

## インストール

- packer.nvim

```lua:packer.nvim
use({ 'tar80/mug.nvim',
  config = function()
    require('mug').setup({
    ...,
    variables = {
      ...
      },
    })
  end,
})
```

## 機能

mug.nvim を導入するとバッファのカレントディレクトリが常に git リポジトリのルート、
または(git リポジトリでなければ)親ディレクトリを指すようになります。
この機能は[mattn/vim-findroot](https://github.com/mattn/vim-findroot)をベースにしていますがいくつか異なる点があります。
詳細は[MugFindroot](#MugFindroot)をご覧下さい。

<details>
<summary>MugFloat</summary>

mug が生成するフローティングウィンドウ(MugFloat)には其々のコマンドで使用するキーマップの他に、
一律で以下のキーマップが設定されます。また、MugFloat が存在する間`<C-W>p`が上書きされ
MugFloat のフォーカスに割り当てられます。

| キー             | 説明           |
| :--------------- | :------------- |
| q, \<ESC>        | フロート閉じる |
| g?               | キーマップ参照 |
| \<count>M-[hjkl] | フロート移動   |

**variables**

- float_winblend (上書き)  
  背景の疑似透過性を指定します。

[float.webm](https://user-images.githubusercontent.com/45842304/218292617-887a15b2-39dd-41c3-8ca0-fc913868c0b5.webm)

</details>

## コマンド

**標準コマンド**

<details>
<summary>MugFindroot</summary>

```lua:
require('mug').setup({
  variables = {
    root_patterns = { '.git/', '.gitignore' },
    ignore_filetypes = { 'git', 'gitcommit', 'gitrebase' },
  }
})
```

**:MugFindroot [stopglobal|stoplocal]**

mug の標準機能です。[mattn/vim-findroot](https://github.com/mattn/vim-findroot) をベースに独自の変更を加えてあります。

- vim-findroot は標準で様々なプロジェクトルートマーカーに対応していますが、mug が対応するのは git のみです。
  また、ディレクトリを下層へ移動する時に動作を抑制するオプションはありません。

- MugFindroot は自動実行されます。手動実行時には実行結果の詳細が出力されます。
  引数`stopglobal` `stoplocal`を指定すると其々`g:mug_findroot_disable=v:true` `b:mug_findroot_disable=v:true`が設定され
  自動実行を抑制します。解除は`MugFindroot`、または`unlet g:mug_findroot_disable` `unlet b:mug_findroot_disable`を実行します。

- MugFindroot が git リポジトリを検知したとき、ブランチ名、ブランチのデタッチ状態、インデックスを取得し、
  其々`b:mug_branch_name` `b:mug_branch_info` `b:mug_branch_stats`を設定します。
  `b:mug_branch_stats`はインデックスの状態をテーブル{ s = stage, u = unstate, c = conflict }として保持します。
  ブランチのキャッシュ・デタッチ状態の取得は[kana/vim-g/branch](https://github.com/kana/vim-g)の機能を取り入れています。

**variables**

- root_patterns (上書き)

  記述フォーマットは vim-findroot の root marker patterns に倣います。優先度があり、先に記述されたパターンが優先されます。
  以下のようなディレクトリ構造を持つファイル file.vim を開いたときにカレントディレクトリは
  `root_patterns`の値により、表のように設定されます。

  ```text:
  main/
    ├ .git/
    ├ submodule/
    │   ├ .git/
    │   ├ script/
    │   │   ├ .gitignore
    │   │   └ file.vim
    │   └ .gitignore
    ├ .gitmodules
    └ .gitignore
  ```

  | root_patterns                  | current directory     |
  | :----------------------------- | :-------------------- |
  | .gitmodules, .git/, .gitignore | main                  |
  | .git/, .gitignore              | main/submodule        |
  | .gitignore                     | main/submodule/script |

- ignore_filetypes (追加)

  指定したファイルタイプは MugFindroot 自動実行の対象外となります。
  ファイルタイプに`*`(ワイルドカード)は指定できません。

</details>
<details>
<summary>Edit</summary>

```lua:
require('mug').setup({
  variables = {
    edit_command = 'Edit',
  }
})
```

**:Edit [!] [\<filespec>]**

カレントファイルの親ディレクトリを基準に`:edit[!] [<filespec>]`を実行します。

**variables**

- edit_command (上書き)

  コマンド`Edit`を別名で登録します。コマンドが不要であれば`""`空文字を指定します。

</details>
<details>
<summary>File</summary>

```lua:
require('mug').setup({
  variables = {
    file_command = 'File',
  }
})
```

**:File[!] \<newname>**

カレントファイルの親ディレクトリを基準に`:file[!] <newname>`を実行します。

**variables**

- file_command (上書き)

  コマンド`File`を別名で登録します。コマンドが不要であれば`""`空文字を指定します。

</details>
<details>
<summary>Write</summary>

```lua:
require('mug').setup({
  variables = {
    write_command = 'Write'
  }
})
```

**:Write[!]**

`:update | git add`を実行します。`!`を付けると`--force`が付加されます。

**variables**

- write_command (上書き)

  コマンド`Write`を別名で登録します。コマンドが不要であれば`""`空文字を指定します。

</details>

**無効化されているコマンド**

<details>
<summary>MugCommit</summary>

```lua:
require('mug').setup({
  commit = true,
  variables = {
    strftime = '%c',
    commit_notation = 'none',
    commit_diffcached_height = 20,
  }
})
```

**:MugCommit[!] [\<sub-command>] [\<commit-message>]**

引数なしで実行するとコミット編集バッファを開きます。`!`を付けると最初に`git add .`を実行します。  
`<sub-command>`には以下のいずれかを指定できます。

- `amend` ステージされた変更を HEAD に追加します。
- `empty` 空コミットを作成します。コミットメッセージには"empty commit(created by mug)"が設定されます。
- `fixup` コミット選択フローティングウィンドウが起動します。\<CR>で選択したコミットを対象にコミットメッセージ"fixup! \<commit>"が設定されます。
- `m <commit-message>` 直接コミットメッセージを入力できます。スペースを含む場合でも""で括る必要はありません。

**コミット編集バッファ**

コミットメッセージの詳細編集用に、`commit_notation`で指定したテンプレート(COMMIT_EDITMSG)をタブで開きます。  
コミット編集バッファには、スペルチェック、短縮入力、キーマップが設定されます。

| モード |      キー       | 説明                           |
| :----: | :-------------: | :----------------------------- |
|   n    |        ^        | スペルチェックをトグル         |
|  n,i   |       F5        | 時刻の挿入                     |
|   n    |       F6        | 差分バッファを水平方向にトグル |
|   n    |       F7        | 差分バッファを縦方向にトグル   |
|   n    | q(差分バッファ) | 差分バッファ閉じる             |

NOTE: 差分バッファはトグルしても更新されません。更新が必要なときは`:bwipeout`で一度完全に削除します。

コミット編集バッファは`git commit`で開かれたバッファではないため如何なる変更もリポジトリに影響を与えません。
コミットの作成にはコマンドを使用します。

- `:C` commit
- `:CA` commit amend
- `:CE` commit empty

**variables**

- strftime (上書き)

  `<F5>`で挿入する時刻の書式を指定します。

- commit_notation (上書き)

  コミットの形式を指定します。`conventional` `genaral` `none`が指定でき、
  指定した形式に合わせたコミットテンプレートと短縮入力が設定されます。  
  また、`mug/lua/template/`内に`<user-template>`と`<user-template>.lua`を作成し、
  `commit_notation = <user-template>`を指定することでユーザー設定が適用されます。
  `<user-template>`はコミットテンプレート、`<user-template>.lua`は短縮入力の設定です。
  スクリプト内`M.additional_settings`に関数を設定すれば、キーマップやコマンドを追加することもできます。
  記述方法は他のテンプレートを参考にしてください。

- commit_diffcached_height (上書き)

  `<F6>`で開く差分バッファの高さを指定します。

**highlights**

`MugCommit fixup`で使用

- MugLogHash `Special`
- MugLogDate `Statement`
- MugLogOwner `Conditional`
- MugLogHead `Keyword`

[commit.webm](https://user-images.githubusercontent.com/45842304/222901039-977a589f-6d05-4dc1-9fdf-7af001c971e5.webm)

</details>
<details>
<summary>MugConfilct</summary>

```lua:
require('mug').setup({
  conflict = true,
  variables = {
    loclist_position = 'left',
    loclist_disable_number = ,
    filewin_beacon = '@@',
    filewin_indicate_position = 'center',
    conflict_begin = '^<<<<<<< ',
    conflict_anc = '^||||||| ',
    conflict_sep = '^=======$',
    conflict_end = '^>>>>>>> '
  }
})
```

**:MugConflict**

新規タブを開き、`git merge`によってコンクリクトしたハンクを抽出、ロケーションリストに展開します。  
[rhysd/conflict-marker.vim](https://github.com/rhysd/conflict-marker.vim/)と似たような操作をロケーションリスト上で実行できます。
conflict-marker は、コンフリクトのあるバッファに対してキーが設定されますが、
MugConflict はロケーションリストにキーを設定します。

- ロケーションリストの表示中は`g:mug_loclist_loaded=v:true`が設定されます。
- ロケーションリストでカーソル移動するとファイルウインドウの表示位置が連動します。
- `<CR>`を押すと、カーソルと表示位置を Ours-Theirs 間で往復します。
- `w`(更新内容を保存)実行後に全てのコンフリクトが解消されていた場合、継続してコミットの作成を促す選択肢を表示します。
- undo/redo は仮対応しています。ハイライトが一致しなかったりします。
- conflict-marker と併用できます。MugConflict 実行時は重複するハイライトが上書きされます。

|      キー      | 説明                                      |
| :------------: | :---------------------------------------- |
|       q        | タブ閉じる                                |
|       w        | すべての更新内容を保存                    |
|       g?       | キーマップ参照                            |
|       o        | Ours-commit の差分でハンクを置き換え      |
|       t        | Theirs-commit の差分でハンクを置き換え    |
|       b        | Base-commit の差分でハンクを置き換え      |
|       B        | Ours, Theirs 両方の差分でハンクを置き換え |
|       ^        | filewindow の連動状態をトグル             |
| \<C-u>, \<C-d> | filewindow のカーソルを 1/2 ページ移動    |
| \<C-j>, \<C-k> | filewindow のカーソルを 1 行移動          |

**variables**

- loclist_position (上書き)  
  ロケーションリストの表示位置を指定します。

- loclist_disable_number (上書き)  
  ロケーションリストの行番号を非表示にするなら`true`を指定します。

- filewin_beacon (上書き)  
  ハンクの開始位置(signcolumn)に表示される文字を指定します。

- filewin_indicate_position (上書き)  
  ファイルウインドウ連動時の、ハンクの画面上の位置です。  
  `upper` `center` `lower`から指定します。

**highlights**

- MugConflictBeacon `Search`
- MugConflictHeader `fg=#777777 bg=#000000`
- MugConflictBase `DiffDelete`
- MugConflictTheirs `DiffAdd`
- MugConflictOurs `DiffChange`
- MugConflictBoth `Normal`をベースに赤と緑を強調した色

[conflict.webm](https://user-images.githubusercontent.com/45842304/222901105-84ba9c08-9f06-4bd9-ab33-701f8df9c4ac.webm)

</details>
<details>
<summary>MugDiff</summary>

```lua:
require('mug').setup({
  diff = true,
  variables = {
    diff_position = ,
  }
})
```

カレントファイルと指定した tree-ish との差分を vimdiff で表示します。  
差分バッファの表示中は独自のキーマップが割り当てられます。

| モード | キー | 説明                |
| :----: | :--: | :------------------ |
|  n,x   |  du  | `Diffupdate`を実行  |
|   x    |  do  | 選択範囲を`Diffget` |
|   x    |  dp  | 選択範囲を`Diffput` |
|   x    |  dd  | 選択範囲を削除      |

**:MugDiff [\<posotion>] [\<treeish>] [\<pathspec>]**

`<position>`に`:new`バッファを開き、`git cat-file -p <treeish>:<pathspec>`の結果を展開します。

- 引数`<position>`は、差分バッファを開く位置です。カレントバッファを起点に`top` `bottom` `left` `right`を指定できます。
  初期値は`diffopt`の値から決定されます。また、`diff_position`で標準の位置を指定できます。
- 引数`<treeish>`の初期値は`""`(空文字)です。
- 引数`<pathspec>`の初期値は`%`です。

**:MugDiffFetchRemote [\<posotion>] [\<branchname>] [\<pathspec>]**

`git fetch orgin <branchname>`を実行後、`<position>`に`:new`バッファを開き、`git cat-file -p origin/<branchname>:<pathspec>`の結果を展開します。

- 引数`<branchname>`の初期値は現在アクティブなブランチ名です。

**variables**

- diff_position (上書き)

  `<position>`のデファルト値を`top` `bottom` `left` `right`のいずれかに設定できます。

</details>
<details>
<summary>MugFiles</summary>

```lua:
require('mug').setup({
  files = true,
})
```

**:MugFileMove[!] \<pathspec>**

カレントファイルに対し`git mv <current-filepath> <pathspec>`を適用し、バッファを開き直します。
`<pathspec>`はカレントディレクトリを基準とします。  
`!`を付けると`--force`が付加されます。

**:MugFileRename[!] \<newname>**

カレントファイルに対し`git -C <parent-directory> mv <current-filename> <newname>`を適用し、バッファを開き直します。
`<newname>`はカレントファイルの親ディレクトリを基準とし、パスの指定はできません。  
`!`を付けると`--force`が付加されます。

**:MugFileDelete[!]**

カレントファイルをリポジトリのインデックスから削除します。  
`!`を付けるとファイル自体も削除されます。

</details>
<details>
<summary>MugIndex</summary>

```lua:
require('mug').setup({
  index = true,
  variables = {
    index_add_key = 'a',
    index_force_key = 'f',
    index_reset_key = 'r',
    index_clear_key = 'c',
    index_input_bar = '@',
    index_commit = '`',
  }
})
```

**:MugIndex[!]**

`git status`の結果をフローティングウインドウに出力します。`!`を付けると`--ignored`が付加されます。  
行ごとに Stage・Unstage・Force stage を選択でき、`<CR>`で実行されます。一番上の行を選択すると全体が選択状態になり、
最下行にはエラーが表示されます。  
MugIndex ウインドウには独自のキーマップが割り当てられます。

|  キー   | 説明                          |
| :-----: | :---------------------------- |
|    a    | 行を選択(Stage)               |
|    f    | 行を選択(Force stage)         |
|    r    | 行を選択(Unstage)             |
|    c    | 選択状態をクリア              |
|  J, K   | 行を選択(Stage)後カーソル移動 |
|   gf    | 行のパスを開く                |
|   gd    | 行のパスを`MugDiff`           |
|    @    | コミットメッセージ入力バー    |
| shift+@ | `MugCommit`を実行             |

**variables**

- index_add_key (上書き)

  行選択(Stage)に使用するキーを指定します。

- index_force_key (上書き)

  行選択(Force stage)に使用するキーを指定します。

- index_reset_kye (上書き)

  行選択(Reset)に使用するキーを指定します。

- index_clear_key (上書き)

  選択状態をクリアするキーを指定します。

- index_input_bar (上書き)

  コミット入力バーの呼び出しキーを指定します。

- index_commit (上書き)

  `MugCommit`の実行キーを指定します。

**highlights**

- MugIndexHeader `String`
- MugIndexStage `Statement`
- MugIndexUnstage `ErrorMsg`
- MugIndexWarning `ErrorMsg`

[index.webm](https://user-images.githubusercontent.com/45842304/222901145-ee3044e0-3206-4936-8130-e319d84ac95d.webm)

</details>
<details>
<summary>MugMerge</summary>

```lua:
require('mug').setup({
  MugMerge = true,
})
```

**:MugMerge[!] \<branchname> [\<options>]**

コミットを作って、カレントブランチに\<branchname>をマージ。  
`git -c merge.conflictstyle=diff3 merge --no-ff [<options>] <branchname>`を実行し、コミットメッセージの編集を確認する選択肢を表示します。
コンフリクト発生時には、処理を継続するか中止するかの選択肢を表示します。  
[!]を付けると、\<options>の補完候補が`--strategy-option=ours` `--strategy-option=theirs`の二択になります。
また、マージ継続中は補完候補が`--abort` `--continue` `--quit`の三択になります。

**:MugMergeFF[!] \<branchname> [\<options>]**

コミットは作らず、カレントブランチに\<branchname>をマージ。  
`git merge --ff-only [<options>] <branchname>`を実行します。コンフリクト発生時はエラーを返します。  
[!]を付けると、\<options>の補完候補が`--strategy-option=ours` `--strategy-option=theirs`の二択になります。

**:MugMergeTo[!] \<branchname>**

コミットは作らず、カレントブランチを\<branchname>にマージ。  
`git fetch . <current-branch>:<branchname>`を実行します。コンフリクト発生時はエラーを返します。  
[!]を付けると、`--force`が付加されます。

[merge.webm](https://user-images.githubusercontent.com/45842304/222901247-1a4937b7-a54c-405c-9d33-7eb9cb1734c9.webm)

</details>
<details>
<summary>MugMkrepo</summary>

```lua:
require('mug').setup({
  mkrepo = true,
  variables = {
    remote_url = ,
    commit_initial_message = 'Initial commit',
  }
})
```

**:MugMkrepo [!] [\<pathspec>]**

指定したパスにリポジトリを作成後、`Initial commit`を作成し、上流ブランチを設定します。  
引数なしのときはカレントファイルの親ディレクトリに、パスを指定したときはそのパスに、名前を指定したときは
カレントファイルの親ディレクトリ下にその名前で、リポジトリを作成します。  
`!`を付けるとパス内のファイルを含めた`Initial commit`を作成します。  
すでにリポジトリが存在していたときはエラーを返します。

**variables**

- remote_url (上書き)

  リモートブランチの URL。HTTPS または、SSH を指定します。  
  未設定の場合、上流ブランチの設定は失敗します。

- commit_initial_message (上書き)

  初期化コミットに使用されるメッセージを指定します。

[mkrepo.webm](https://user-images.githubusercontent.com/45842304/219909055-10a63d23-597e-4008-a427-d67c226628c8.webm)

</details>
<details>
<summary>MugShow</summary>

```lua:
require('mug').setup({
  show = true,
  }
})
```

**:MugShow[!] \<any>**

MugShow は git とは関連のないコマンドです。引数に指定した変数、関数、コマンドの結果をフローティングウインドウに出力します。
なんでもは表示できませんがそこそこ表示されます。  
引数入力時の接頭辞(接尾辞)によって、補完候補と出力対象が選択されます。関数には引数も指定できます。
補完候補は完全には対応できていません。

| 接頭辞       | 出力対象       | 使用例                       |
| :----------- | :------------- | :--------------------------- |
| `$`          | 環境変数       | `$vim`                       |
| `_G.`        | lua 変数       | `_G._VERSION`                |
| `[gwbtv]:`   | vim 変数       | `v:version`                  |
| `&`          | vim オプション | `&rtp`                       |
| `vim.`       | 関数           | `vim.loop`, `vim.loop.cwd()` |
| `()`(接尾辞) | vim 関数       | `expand('~')`                |
| `nvim_`      | nvim 関数      | `nvim_list_runtime_paths()`  |
| `:`          | コマンド       | `:version`                   |
| `MugShow!`   | shell コマンド | `ls`, `git show`             |

[show.webm](https://user-images.githubusercontent.com/45842304/222901228-1674129e-630b-40cc-b1b6-31964a560594.webm)

</details>

## 全設定初期値

```lua:
  require('mug').setup({
    commit = false,
    conflict = false,
    diff = false,
    files = false,
    index = false,
    merge = false,
    mkrepo = false,
    show = false,
    variables = {
      -- Float
      float_winblend = 0,

      -- Findroot
      root_patterns = { '.git/', '.gitignore' },
      ignore_filetypes = { 'git', 'gitcommit', 'gitrebase' },

      -- Default commands
      edit_command = 'Edit',
      file_command = 'File',
      write_command = 'Write'

      -- Commit
      strftime = '%c',
      commit_notation = 'none',
      commit_diffcached_height = 20,

      -- Conflict
      conflict_begin = '^<<<<<<< ',
      conflict_anc = '^||||||| ',
      conflict_sep = '^=======$',
      conflict_end = '^>>>>>>> ',
      filewin_beacon = '@@',
      filewin_indicate_position = 'center',
      loclist_position = 'left',
      loclist_disable_number = nil,

      -- Diff
      diff_position,

      -- Index
      index_add_key = 'a',
      index_force_key = 'f',
      index_reset_key = 'r',
      index_clear_key = 'c',
      index_inputbar = '@',
      index_commit = '`',

      -- Mkrepo
      remote_url = nil,
      commit_initial_message = 'Initial commit',
    },
  })
```

## TODO

- [ ] rebase をなんとかしたい
- [ ] テスト そのうち

## 謝辞

mug.nvim は以下の vim-plugin のコードを内包します。  
該当部分のライセンスは其々のプロジェクトのライセンスに従います。

- [mattn/vim-findroot](https://github.com/mattn/vim-findroot)
- [kana/vim-g](https://github.com/kana/vim-g)

また以下のプロジェクトを参考にさせて頂きました。

- [rhysd/conflict-marker.vim](https://github.com/rhysd/conflict-marker.vim/)
- [akinsho/git-conflict.nvim](https://github.com/akinsho/git-conflict.nvim)
- [Rasukarusan/nvim-select-multi-line](https://github.com/Rasukarusan/nvim-select-multi-line)

プロジェクトを公開されておられる作者様に御礼申し上げます。
