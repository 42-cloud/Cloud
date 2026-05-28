FROM wordpress:6.9-php8.3-apache

COPY images/ /tmp/wp-assets/
# COPY posts/ /usr/src/wordpress/posts_templates/

RUN curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp && chmod +x /usr/local/bin/wp