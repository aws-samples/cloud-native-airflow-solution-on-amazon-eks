FROM apache/airflow:slim-2.3.4-python3.10
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         gcc g++ libsasl2-dev libpq-dev  \
    && apt-get autoremove -yqq --purge \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
USER airflow
RUN pip install --no-cache-dir \
      apache-airflow-providers-apache-hive==4.0.0 apache-airflow-providers-amazon==5.1.0 \
      'apache-airflow[celery]' 'apache-airflow[statsd]' \
      psycopg2==2.9.3 Redis==4.3.4 \
    && rm -fr /tmp/*
