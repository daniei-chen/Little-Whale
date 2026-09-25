# 本地构建配置 —— 示例。
#
# 复制成 tools/build.config.ps1 再改成你自己的地址（那个文件不进仓库）。
# 不想配置就直接构建：App 会跳过更新检查，其它功能都正常。

@{
    UpdateUrl    = 'https://你的域名/app/version.json'
    UpdateUrlAlt = 'https://cdn.jsdelivr.net/gh/你的用户名/你的仓库@main/server/version.json'
    DownloadPage = 'https://你的域名/app/'
    DownloadBase = 'https://你的域名/app/download'
    ServerHost   = ''          # scp 目标，留空则不发版到服务器
    ServerDir    = ''
    JavaHome     = ''          # 留空则用环境变量 JAVA_HOME
}