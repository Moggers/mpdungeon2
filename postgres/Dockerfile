FROM postgres
RUN <<EOF
apt-get update
apt-get install -y make git g++
EOF
RUN apt-get install -y postgresql-server-dev-17
RUN apt-get install -y libcurl4-gnutls-dev
RUN <<EOF
git clone https://github.com/DataDog/pg_tracing.git
cd pg_tracing
make install
# To compile and install with debug symbols:
PG_CFLAGS="-g" make install
EOF
RUN <<EOF
git clone https://github.com/pramsey/pgsql-http.git
cd pgsql-http
make
make install
EOF
COPY ./scripts/* /docker-entrypoint-initdb.d/
