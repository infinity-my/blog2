DROP TABLE IF EXISTS article;
CREATE TABLE article (
    id BIGINT NOT NULL AUTO_INCREMENT,
    title VARCHAR(200) NOT NULL,
    excerpt VARCHAR(1000),
    publish_date DATE NOT NULL,
    category VARCHAR(50) NOT NULL,
    tags VARCHAR(500),
    views INT NOT NULL DEFAULT 0,
    content MEDIUMTEXT,
    PRIMARY KEY (id),
    KEY idx_publish_date (publish_date),
    KEY idx_category (category)
);

DROP TABLE IF EXISTS writing_activity;
CREATE TABLE writing_activity (
    stat_date DATE NOT NULL,
    activity_count INT NOT NULL DEFAULT 0,
    PRIMARY KEY (stat_date)
);

DROP TABLE IF EXISTS site_config;
CREATE TABLE site_config (
    config_key VARCHAR(50) NOT NULL,
    config_value VARCHAR(500) NOT NULL,
    PRIMARY KEY (config_key)
);

DROP TABLE IF EXISTS site_visit;
CREATE TABLE site_visit (
    stat_date DATE NOT NULL,
    visits INT NOT NULL DEFAULT 0,
    PRIMARY KEY (stat_date)
);

DROP TABLE IF EXISTS app_user;
CREATE TABLE app_user (
    id BIGINT NOT NULL AUTO_INCREMENT,
    email VARCHAR(200) NOT NULL,
    name VARCHAR(50) NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_app_user_email (email)
);

-- 后台管理员账号：初始账号由启动时的 AdminAccountSeeder 按 blog.admin.* 配置种入，
-- 表里已有同名账号则跳过；忘了口令删掉对应行再重启即可重新种入
DROP TABLE IF EXISTS admin_account;
CREATE TABLE admin_account (
    id BIGINT NOT NULL AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL,
    display_name VARCHAR(50) NOT NULL,
    password_hash VARCHAR(100) NOT NULL,
    enabled TINYINT(1) NOT NULL DEFAULT 1,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_admin_account_username (username)
);

DROP TABLE IF EXISTS message;
CREATE TABLE message (
    id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL,
    content VARCHAR(500) NOT NULL,
    likes INT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL,
    user_id BIGINT,
    PRIMARY KEY (id),
    KEY idx_created_at (created_at)
);

DROP TABLE IF EXISTS message_reply;
CREATE TABLE message_reply (
    id BIGINT NOT NULL AUTO_INCREMENT,
    message_id BIGINT NOT NULL,
    name VARCHAR(50) NOT NULL,
    content VARCHAR(500) NOT NULL,
    likes INT NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL,
    is_author TINYINT(1) NOT NULL DEFAULT 0,
    reply_to VARCHAR(50),
    user_id BIGINT,
    PRIMARY KEY (id),
    KEY idx_message_id (message_id)
);

DROP TABLE IF EXISTS album_photo;
CREATE TABLE album_photo (
    id BIGINT NOT NULL AUTO_INCREMENT,
    src VARCHAR(300) NOT NULL,
    width INT NOT NULL,
    height INT NOT NULL,
    title VARCHAR(200) NOT NULL,
    shoot_date DATE NOT NULL,
    location VARCHAR(100),
    shot VARCHAR(100),
    caption VARCHAR(1000),
    tags VARCHAR(300),
    PRIMARY KEY (id),
    KEY idx_shoot_date (shoot_date)
);

DROP TABLE IF EXISTS essay;
CREATE TABLE essay (
    id BIGINT NOT NULL AUTO_INCREMENT,
    essay_date DATE NOT NULL,
    mood VARCHAR(20),
    location VARCHAR(100),
    paragraphs VARCHAR(2000),
    images VARCHAR(500),
    tags VARCHAR(300),
    PRIMARY KEY (id),
    KEY idx_essay_date (essay_date)
);

-- 简历整包内容：单行 JSON（profile/metrics/experience/…），解锁后经 /api/resume/content 下发
DROP TABLE IF EXISTS resume_content;
CREATE TABLE resume_content (
    id BIGINT NOT NULL AUTO_INCREMENT,
    payload MEDIUMTEXT NOT NULL,
    updated_at DATETIME NOT NULL,
    PRIMARY KEY (id)
);

-- 文章评论：只允许登录用户发言，身份在服务端裁决；计数由接口实时统计，不落冗余列
DROP TABLE IF EXISTS comment;
CREATE TABLE comment (
    id BIGINT NOT NULL AUTO_INCREMENT,
    article_id BIGINT NOT NULL,
    user_id BIGINT,
    name VARCHAR(50) NOT NULL,
    content VARCHAR(500) NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    KEY idx_comment_article (article_id)
);

-- 点赞记录：按访客（登录用户 u:{userId} / 匿名 cookie v:{uuid}）幂等去重，
-- 计数增减由接口按记录裁决，绕过前端连点也不会刷数
DROP TABLE IF EXISTS like_record;
CREATE TABLE like_record (
    id BIGINT NOT NULL AUTO_INCREMENT,
    target_type VARCHAR(20) NOT NULL,
    target_id BIGINT NOT NULL,
    visitor_key VARCHAR(80) NOT NULL,
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_like_target_visitor (target_type, target_id, visitor_key)
);

-- 访客行为记录：只记有意义的行为（打开文档/项目、评论、留言、点赞），
-- 普通页面导航不上报。action 取值：post / project / comment / message / like；
-- detail 存行为的内容摘要（评论文本、留言文本、点赞对象），浏览类为 NULL。
-- visitor_key 与点赞同一套身份（登录用户 u:{userId} / 匿名 cookie v:{uuid}），
-- user_id 冗余存一份，按注册用户聚合时不用再解析 key
DROP TABLE IF EXISTS visit_log;
CREATE TABLE visit_log (
    id BIGINT NOT NULL AUTO_INCREMENT,
    visitor_key VARCHAR(80) NOT NULL,
    user_id BIGINT,
    action VARCHAR(20) NOT NULL DEFAULT 'post',
    path VARCHAR(300) NOT NULL,
    title VARCHAR(200),
    detail VARCHAR(500),
    created_at DATETIME NOT NULL,
    PRIMARY KEY (id),
    KEY idx_visit_visitor (visitor_key, created_at),
    KEY idx_visit_user (user_id),
    KEY idx_visit_action (action, created_at)
);

-- 全站共用的标签池：标签管理页维护，名称的唯一事实在这里；
-- 文章/随笔/照片的 tags 列只存名称，改名/删除由 TagPool 同步回内容
DROP TABLE IF EXISTS tag;
CREATE TABLE tag (
    id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(50) NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uk_tag_name (name)
);

-- 项目展示：前台「项目」页与详情页的数据源。slug 用于详情路由 /projects/:slug；
-- stack 为技术栈 JSON 数组；readme 为 markdown 源文本；sort_order 数字越小越靠前，
-- visible=0 时前台列表与详情均不展示
DROP TABLE IF EXISTS project;
CREATE TABLE project (
    id BIGINT NOT NULL AUTO_INCREMENT,
    name VARCHAR(100) NOT NULL,
    slug VARCHAR(100) NOT NULL,
    description VARCHAR(500) NOT NULL,
    stack VARCHAR(300),
    status VARCHAR(20) NOT NULL,
    repo VARCHAR(300),
    demo VARCHAR(300),
    period VARCHAR(50),
    role VARCHAR(50),
    readme MEDIUMTEXT,
    sort_order INT NOT NULL DEFAULT 0,
    visible TINYINT(1) NOT NULL DEFAULT 1,
    PRIMARY KEY (id),
    UNIQUE KEY uk_project_slug (slug),
    KEY idx_project_sort (sort_order)
);
