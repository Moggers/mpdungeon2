echo "\
shared_preload_libraries = 'pg_tracing,pg_cron'
compute_query_id = on
pg_tracing.max_span = 10000
pg_tracing.track = all
pg_tracing.sample_rate = 1.0
pg_tracing.otel_endpoint = http://jaeger:4318/v1/traces
pg_tracing.otel_naptime = 2000

http.curlopt_timeout = 200

openai.api_uri = 'http://ollama:11434/v1/'
openai.api_key = 'none'
openai.prompt_model = 'mistral-small3.1'
openai.embedding_model = 'mxbai-embed-large'
cron.database_name = 'postgres'
" >> /var/lib/postgresql/data/postgresql.conf

