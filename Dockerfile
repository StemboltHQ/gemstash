FROM alpine:latest

RUN apk add --update ca-certificates build-base ruby ruby-dev sqlite sqlite-dev openssl openssl-dev && rm -rf /var/cache/apk/*

RUN gem install gemstash -v 1.0.0.pre.1
RUN mkdir ~/.gemstash && echo -e > ~/.gemstash/config.yml "\
--- \n\
:base_path: '/data'"

VOLUME "/data"

EXPOSE 9292

CMD ["/usr/bin/gemstash", "start", "--no-daemonize"]
