# 数据字典：YouTube Trending Videos Dataset

**数据源**：Kaggle `thedevastator/youtube-trending-videos-dataset`，`youtube.csv`
**粒度**：一行 = 一个视频在一个国家的某一天上了热搜榜（事件粒度 event grain）
**唯一键（清洗后）**：`(video_id, publish_country, trend_dt)`

18 个字段，每个字段列出：真实含义、类型、取值范围、验证 SQL、与 Kaggle 官方说明的差异。

---

## 1. `index`

- **真实含义**：行序号，DuckDB 导入 CSV 时的行号，从 0 开始
- **类型**：BIGINT
- **取值范围**：0 到 161,469（等于总行数 - 1）
- **验证 SQL**：`SELECT COUNT(DISTINCT index) FROM raw` → 应等于总行数 161,470
- **与官方说明差异**：无特别说明，行为符合预期

## 2. `video_id`

- **真实含义**：YouTube 视频 ID，理论上是主键的一部分
- **类型**：VARCHAR
- **取值范围**：55,886 个 distinct 值（含 `#NAME?`）
- **验证 SQL**：`SELECT COUNT(*) FROM raw WHERE video_id = '#NAME?'` → 1,799
- **与官方说明差异**：**存在已知坏值 `#NAME?`**（Excel 把以 `-`/`=` 开头的 ID 当公式处理后留下的错误值），代表几百个不同视频挤在一起，必须整体隔离，不能信任

## 3. `trending_date`

- **真实含义**：这一行快照对应的日期，格式是 `YY.DD.MM`（年.日.月，不是常见的年.月.日）
- **类型**：VARCHAR（⚠️ **不是 DATE**，DuckDB `read_csv_auto` 认不出这个非标准格式，会当字符串处理）
- **取值范围**：`17.01.12`（2017-12-01）到 `18.31.05`（2018-05-31），205 个 distinct 值
- **验证 SQL**：`SELECT strptime(trending_date, '%y.%d.%m')::DATE FROM raw LIMIT 5` 确认能正确转换
- **与官方说明差异**：**格式陷阱**。必须显式用 `strptime(trending_date, '%y.%d.%m')::DATE` 转换成真正的日期类型，否则所有涉及日期比较、排序、窗口函数的查询都会出错或给出误导性结果（字符串排序和日期排序不一致）

## 4. `title`

- **真实含义**：视频标题快照（不是恒定属性，同一视频改标题后新标题会出现在后续行）
- **类型**：VARCHAR
- **取值范围**：56,905 个 distinct 值，含大量 emoji 和多语言字符（部分显示为乱码，是 CSV 编码问题）
- **验证 SQL**：`SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT title)>1)` → 538 个视频改过标题
- **与官方说明差异**：官方未强调这是"跨行可变"的属性列，取值时应用 `ARG_MAX(title, trend_dt)` 取末次快照，不能用 `ANY_VALUE`

## 5. `channel_title`

- **真实含义**：发布该视频的频道名称快照（同样跨行可变，会因改名而不同）
- **类型**：VARCHAR
- **取值范围**：原始表 12,361 个 distinct 值；⚠️ **不是主键**，数据集没有 `channel_id`，只能按标题分组，52-53 组标题仅大小写或空格不同会被误判为不同频道
- **验证 SQL**：`SELECT COUNT(*) FROM (SELECT video_id FROM clean GROUP BY 1 HAVING COUNT(DISTINCT channel_title)>1)` → 55 个视频改过频道名
- **与官方说明差异**：Kaggle 页面容易让人误以为 `channel_title` 可以当频道的唯一标识，**实际上不行**——55 个视频改过频道名，52-53 组标题因大小写/空格差异被误判成不同频道。这是频道级分析的已知缺陷，写进局限里

## 6. `category_id`

- **真实含义**：YouTube 视频品类的数字编码
- **类型**：BIGINT
- **取值范围**：18 个整数（1 到 44 之间，不连续），**无对应的名称映射**
- **验证 SQL**：`SELECT DISTINCT category_id FROM raw ORDER BY 1` → 18 行
- **与官方说明差异**：本数据集**不带**品类名称映射表。真实的 ID→名称映射来自上游 `datasnaek` 系列数据集里的 `*_category_id.json` 文件（YouTube API 的标准品类表），需要单独下载补充；不能凭空猜测数字对应的品类名

## 7. `publish_date`

- **真实含义**：视频最初发布的日期（属性列，不随抓取变化）
- **类型**：DATE（这一列 DuckDB 能正确识别）
- **取值范围**：2006-07-23 到 2018-06-14，471 个 distinct 值
- **验证 SQL**：`SELECT video_id FROM raw WHERE video_id<>'#NAME?' GROUP BY 1 HAVING COUNT(DISTINCT publish_date)>1` → 11 个 ID 违反"发布日期应恒定"
- **与官方说明差异**：无字段含义争议，但是不变量 2 的关键列——11 个 video_id 的 `publish_date` 跨行不恒定，是发布属性不干净的信号

## 8. `time_frame`

- **真实含义**：视频的 **UTC 发布钟点**（比如 `17:00 to 17:59` 表示 UTC 17 点发布），是"发布时刻"不是"持续时长"
- **类型**：VARCHAR
- **取值范围**：24 个整点区间取值，从 `0:00 to 0:59` 到 `23:00 to 23:59`
- **验证 SQL**：见 `sql/00-invariants.sql` 证据 1-3
- **与官方说明差异**：**Kaggle 官方描述为"视频热搜的时间长短"，这是错的**。三条证据（只有 24 个整点取值、同一视频跨行不变、US 榜 `time_frame='0:00 to 0:59'` 却有连续上榜 22 天的反例）证明它是发布钟点，不是时长。本项目的所有分析文档都已改用 `pub_hour_utc` 这个更准确的别名

## 9. `published_day_of_week`

- **真实含义**：`publish_date` 对应的星期几（冗余列，可以从 `publish_date` 推导，但直接读省事）
- **类型**：VARCHAR
- **取值范围**：7 个值（Monday 到 Sunday）
- **验证 SQL**：`SELECT published_day_of_week, DAYNAME(publish_date) FROM raw LIMIT 5` 交叉验证两者是否一致
- **与官方说明差异**：无差异，是本项目 POC-03 假设检验的关键分组字段（周五 vs 非周五）

## 10. `publish_country`

- **真实含义**：这一行快照来自哪个国家的热搜榜
- **类型**：VARCHAR
- **取值范围**：4 个值（US, CANADA, FRANCE, GB）
- **验证 SQL**：`SELECT DISTINCT publish_country FROM raw` → 4 行
- **与官方说明差异**：无差异，是本项目最核心的分层维度——四国是两种完全不同的榜单机制（一日游占比 59-75% vs 7-11%）

## 11. `tags`

- **真实含义**：视频标签，用 `"` 分隔的字符串拼接（不是标准 JSON 数组）
- **类型**：VARCHAR
- **取值范围**：50,239 个 distinct 组合，含多语言和特殊字符
- **验证 SQL**：`SELECT tags FROM raw LIMIT 3` 观察实际格式
- **与官方说明差异**：本项目 In Scope 未使用这一列做正式分析，仅作为已知字段列入字典

## 12. `views`

- **真实含义**：这一行快照时刻的累计观看数
- **类型**：BIGINT
- **取值范围**：223 到 424,538,912
- **验证 SQL**：`SELECT COUNT(*) FROM (SELECT views, LAG(views) OVER (...) AS prev FROM clean) WHERE views < prev` → 100 行倒退
- **与官方说明差异**：无字段含义争议，但有 **100 行倒退**（比前一日快照小），是上游快照顺序或缓存问题，不是视频真的"掉观看数"

## 13. `likes`

- **真实含义**：这一行快照时刻的累计点赞数
- **类型**：BIGINT
- **取值范围**：0 到 5,613,827
- **验证 SQL**：无单独验证，配合 `views` 用于去重排序（`ORDER BY views DESC, likes DESC`）
- **与官方说明差异**：无

## 14. `dislikes`

- **真实含义**：这一行快照时刻的累计点踩数
- **类型**：BIGINT
- **取值范围**：0 到 1,944,971
- **验证 SQL**：无
- **与官方说明差异**：无，本项目未使用这一列做核心指标

## 15. `comment_count`

- **真实含义**：这一行快照时刻的累计评论数
- **类型**：BIGINT
- **取值范围**：0 到 1,626,501
- **验证 SQL**：无
- **与官方说明差异**：无

## 16. `comments_disabled`

- **真实含义**：该视频是否关闭了评论
- **类型**：BOOLEAN
- **取值范围**：True / False
- **验证 SQL**：`SELECT comments_disabled, COUNT(*) FROM raw GROUP BY 1`
- **与官方说明差异**：无，是运营可执行建议候选之一（"是否关评论"，见 case §二映射表）

## 17. `ratings_disabled`

- **真实含义**：该视频是否关闭了点赞/点踩功能
- **类型**：BOOLEAN
- **取值范围**：True / False
- **验证 SQL**：`SELECT ratings_disabled, COUNT(*) FROM raw GROUP BY 1`
- **与官方说明差异**：无

## 18. `video_error_or_removed`

- **真实含义**：该视频在抓取时是否报错或已被删除
- **类型**：BOOLEAN
- **取值范围**：True / False，126 行为 True（清洗后）
- **验证 SQL**：`SELECT COUNT(*) FROM clean WHERE video_error_or_removed = True` → 126
- **与官方说明差异**：无字段含义争议，但**计算留存/寿命类指标时需要考虑是否剔除这 126 行**，因为它们的 `views` 等指标可能已经失真（视频被删后快照仍残留）

---

## 已知的两个结构性缺陷（不在本项目内修复，但必须写清楚）

1. **`category_id` 没有名称映射**：本数据集不带，需要从上游 `datasnaek` 系列数据集的 `*_category_id.json` 单独下载
2. **`channel_title` 不是主键**：数据集没有 `channel_id`，52-53 组标题仅因大小写/空格不同就被误判为不同频道；另有 55 个视频在榜期间改过频道名，按末次快照归到最后的名字下，早期上榜记录会"转移"给新名字

---

**产出**：本字典 + `docs/data-quality-report.md` + `sql/00-invariants.sql`
