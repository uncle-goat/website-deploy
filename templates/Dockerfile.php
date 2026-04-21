# =============================================================================
# PHP Dockerfile
# =============================================================================
# 用途：构建并运行 PHP-FPM 应用
# 架构说明：PHP-FPM 容器处理 PHP 逻辑，需配合 Nginx 容器提供 HTTP 服务
#          推荐使用 docker-compose 编排两个容器（参见 docker-compose.fullstack）
# 使用方式：根据项目实际情况替换 {{VARIABLE}} 占位符
# =============================================================================

FROM php:8.2-fpm-alpine

# ---------------------------------------------------------------------------
# 安装 PHP 扩展
# ---------------------------------------------------------------------------
# 根据项目需求取消注释并添加所需扩展
# 格式：docker-php-ext-install <扩展名>
# 常用扩展：pdo_mysql pdo_pgsql mysqli gd zip opcache bcmath exif intl
RUN apk add --no-cache \
        libpng-dev \
        libjpeg-turbo-dev \
        freetype-dev \
        libzip-dev \
        icu-dev \
        postgresql-dev \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-install -j$(nproc) \
        pdo \
        pdo_mysql \
        pdo_pgsql \
        mysqli \
        gd \
        zip \
        opcache \
        bcmath \
    && rm -rf /var/lib/apt/lists/* /tmp/*

# ---------------------------------------------------------------------------
# 安装 Composer（PHP 包管理器）
# ---------------------------------------------------------------------------
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# ---------------------------------------------------------------------------
# 配置 PHP 运行时参数
# ---------------------------------------------------------------------------
# 设置时区、内存限制、上传大小等
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/php.ini
RUN sed -i 's|;date.timezone =.*|date.timezone = {{TIMEZONE}}|' /usr/local/etc/php/php.ini && \
    sed -i 's|memory_limit = .*|memory_limit = 256M|' /usr/local/etc/php/php.ini && \
    sed -i 's|upload_max_filesize = .*|upload_max_filesize = 64M|' /usr/local/etc/php/php.ini && \
    sed -i 's|post_max_size = .*|post_max_size = 64M|' /usr/local/etc/php/php.ini && \
    sed -i 's|max_execution_time = .*|max_execution_time = 300|' /usr/local/etc/php/php.ini

# ---------------------------------------------------------------------------
# 配置 OPcache（PHP 字节码缓存，显著提升性能）
# ---------------------------------------------------------------------------
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=16'; \
    echo 'opcache.max_accelerated_files=20000'; \
    echo 'opcache.revalidate_freq=0'; \
    echo 'opcache.validate_timestamps=0'; \
    echo 'opcache.save_comments=1'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
    } > /usr/local/etc/php/conf.d/opcache-recommended.ini

# ---------------------------------------------------------------------------
# 创建非 root 用户
# ---------------------------------------------------------------------------
RUN addgroup -S appuser -g 1001 && \
    adduser -S appuser -u 1001 -G appuser

# ---------------------------------------------------------------------------
# 复制应用代码
# ---------------------------------------------------------------------------
WORKDIR /var/www/html

# 先复制 Composer 依赖文件，利用层缓存
COPY composer.json composer.lock* ./

# 安装 PHP 依赖（生产环境不加 dev 依赖）
RUN composer install --no-dev --no-interaction --optimize-autoloader --no-progress

# 复制项目源代码
COPY . .

# 设置文件权限
RUN chown -R appuser:appuser /var/www/html

# 切换到非 root 用户
USER appuser

# PHP-FPM 默认监听 9000 端口（通过 FastCGI 协议与 Nginx 通信）
EXPOSE 9000

# 健康检查：通过 cgi-fcgi 或脚本检测 PHP-FPM 是否正常响应
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD SCRIPT_NAME=/health SCRIPT_FILENAME=/var/www/html/public/health.php \
        cgi-fcgi -bind -connect 127.0.0.1:9000 || exit 1

# PHP-FPM 前台运行（默认 CMD 已配置）
CMD ["php-fpm"]
