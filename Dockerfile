FROM ruby:3.3-alpine

RUN apk add --no-cache build-base sqlite-dev tzdata

RUN addgroup -S app && adduser -S app -G app

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without 'test' && \
    bundle install --jobs 4 --retry 3

COPY . .

RUN mkdir -p db && chown -R app:app /app

USER app

ENV RACK_ENV=production
EXPOSE 4567

CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:4567"]
