启用选定的配置 (README)

此脚本（enable-selected-packages.sh）用于在仓库根目录下的 hinlink-all 目录中，把一组指定的 CONFIG_ 选项统一设为启用（=y）。

用法：

1. 在本地 clone 仓库并切换到 main 分支：
   git clone https://github.com/googlewmb/Rockchip-H68K.git
   cd Rockchip-H68K
   git checkout main

2. 运行脚本（有修改会写回文件）：
   chmod +x hinlink-all/enable-selected-packages.sh
   ./hinlink-all/enable-selected-packages.sh

3. 提交更改并推送：
   git add hinlink-all/*config*
   git commit -m "Enable selected packages in hinlink-all .config files"
   git push origin main

注意：
- 脚本会尝试删除现有的同名配置行（包括 "CONFIG_X=..."、"# CONFIG_X is not set"），然后把要启用的配置追加到文件末尾。
- 脚本只在本地修改文件；本次提交将添加脚本到仓库，但不会自动替你修改所有 .config 文件——请在本地运行脚本并提交，或回复我允许我直接修改并提交这些文件到仓库（我可以在云端替你进行批量修改，如果你授权我这么做）。
