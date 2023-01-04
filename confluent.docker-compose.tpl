---
{{ $zl := coll.Slice -}}
{{ $zll := coll.Slice -}}
{{ $bs := coll.Slice -}}
{{ $bsi := coll.Slice -}}
{{ range $index, $element := (datasource "config").zookeeper -}}
{{ $combine := (printf "%v:%v" $element.name $element.port) -}}
{{ $c2 := (printf "%v:2888:3888" $element.name) -}}
{{ $zl = $zl | append $combine -}}
{{ $zll = $zll | append $c2 -}}
{{ end -}}
{{ range $index, $element := (datasource "config").kafka -}}
{{ $combine := (printf "%v:%v" $element.name (add $element.port 10000)) -}}
{{ $c2 := (printf "localhost:%v" $element.port) -}}
{{ $bs = $bs | append $combine -}}
{{ $bsi = $bsi | append $c2 -}}
{{ end -}}
# zk: {{ join $zl "," }}
# zk: {{ join $zll ";" }}
# bs: {{ join $bs "," }}
# bsi: {{ join $bsi "," }}
version: '3.8'
services:
{{ range $index, $element := (datasource "config").zookeeper }}
  {{ $element.name }}:
    image: confluentinc/cp-zookeeper:{{ (datasource "config").confluent.version }}
    hostname: {{ $element.name }}
    container_name: {{ $element.name }}
    environment:
      ZOOKEEPER_SERVER_ID: {{ add $index 1 }}
      ZOOKEEPER_CLIENT_PORT: {{ $element.port }}
      ZOOKEEPER_TICK_TIME: "2000"
      ZOOKEEPER_SERVERS: {{ join $zll ";" }}
      KAFKA_JMX_PORT: 9999
      KAFKA_JMX_HOSTNAME: localhost
      KAFKA_OPTS: "-javaagent:/tmp/jmx_prometheus_javaagent-0.12.1.jar=8091:/tmp/zookeeper_config.yml"
    volumes:
      - $PWD/volumes/jmx_prometheus_javaagent-0.12.1.jar:/tmp/jmx_prometheus_javaagent-0.12.1.jar
      - $PWD/volumes/zookeeper_config.yml:/tmp/zookeeper_config.yml
      - $PWD/volumes/jline-2.12.1.jar:/usr/share/java/kafka/jline-2.12.1.jar
    ports:
      - {{ ( add $element.port $index) }}:{{ $element.port }}
{{ end -}}

{{ range $index, $element := (datasource "config").kafka }}
  {{ $element.name }}:
    image: confluentinc/cp-server:{{ (datasource "config").confluent.version }}
    hostname: {{ $element.name }}
    container_name: {{ $element.name }}
    depends_on:
    {{ range $i2, $e2 := (datasource "config").zookeeper -}}
          - {{ $e2.name}}
    {{ end -}}
    environment:
      KAFKA_BROKER_ID: {{ add $index 1 }}
      KAFKA_ZOOKEEPER_CONNECT: {{ join $zl "," }}
      KAFKA_LISTENERS: PLAINTEXT://:{{ add $element.port 10000 }}, EXTERNAL://:{{ $element.port }}
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,EXTERNAL:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://{{ $element.name }}:{{ add $element.port 10000 }}, EXTERNAL://localhost:{{ $element.port }}
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_GROUP_INITIAL_REBALANCE_DELAY_MS: 0
      KAFKA_JMX_PORT: 9999
      KAFKA_JMX_HOSTNAME: {{ $element.name }}
      KAFKA_BROKER_RACK: rack-{{ $index }}
      KAFKA_OPTS: "-javaagent:/tmp/jmx_prometheus_javaagent-0.12.1.jar=8091:/tmp/kafka_config.yml"
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_CONFLUENT_LICENSE_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_CONFLUENT_BALANCER_TOPIC_REPLICATION_FACTOR: 1
      CONFLUENT_METRICS_REPORTER_TOPIC_REPLICAS: 1
    ports:
      - {{ $element.port}}:{{ $element.port}}
    volumes:
      - $PWD/volumes/jmx_prometheus_javaagent-0.12.1.jar:/tmp/jmx_prometheus_javaagent-0.12.1.jar
      - $PWD/volumes/kafka_config.yml:/tmp/kafka_config.yml
{{ end }}
{{ if (datasource "config").sr.enable }}
  schema-registry:
    image: confluentinc/cp-schema-registry:{{ (datasource "config").confluent.version }}
    hostname: {{ (datasource "config").sr.name }}
    container_name: {{ (datasource "config").sr.name }}
    depends_on:
    {{ range $i2, $e2 := (datasource "config").kafka -}}
          - {{ $e2.name}}
    {{ end -}}
    ports:
      - {{ (datasource "config").sr.port }}:{{ (datasource "config").sr.port }}
    environment:
      SCHEMA_REGISTRY_HOST_NAME: schema-registry
      SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS: {{ join $bs "," }}
      SCHEMA_REGISTRY_LISTENERS: "http://0.0.0.0:{{ (datasource "config").sr.port }}"
{{ end -}}

{{ if (datasource "config").connect.enable }}
  connect:
    image: confluentinc/cp-kafka-connect:{{ (datasource "config").confluent.version }}
    hostname: {{ (datasource "config").connect.name }}
    container_name: {{ (datasource "config").connect.name }}
    volumes:
      - ./connect-components:/usr/share/confluent-hub-components
    depends_on:
    {{ range $i2, $e2 := (datasource "config").kafka -}}
        - {{ $e2.name}}
    {{ end -}}
    {{ if (datasource "config").sr.enable -}}
        - {{ (datasource "config").sr.name }}
    {{ end -}}
    ports:
      - {{ (datasource "config").connect.port }}:{{ (datasource "config").connect.port }}
    environment:
      CONNECT_BOOTSTRAP_SERVERS: {{ join $bs "," }}
      CONNECT_REST_ADVERTISED_HOST_NAME: {{ (datasource "config").connect.name }}
      CONNECT_GROUP_ID: compose-connect-group
      CONNECT_CONFIG_STORAGE_TOPIC: docker-connect-configs
      CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_OFFSET_FLUSH_INTERVAL_MS: 10000
      CONNECT_OFFSET_STORAGE_TOPIC: docker-connect-offsets
      CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_STATUS_STORAGE_TOPIC: docker-connect-status
      CONNECT_STATUS_STORAGE_REPLICATION_FACTOR: 1
      CONNECT_KEY_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      #CONNECT_VALUE_CONVERTER: org.apache.kafka.connect.storage.StringConverter
      CONNECT_VALUE_CONVERTER: io.confluent.connect.avro.AvroConverter
      CONNECT_VALUE_CONVERTER_SCHEMA_REGISTRY_URL: http://{{ (datasource "config").sr.name }}:{{ (datasource "config").sr.port }}
      CONNECT_PLUGIN_PATH: "/usr/share/java,/usr/share/confluent-hub-components"
      CONNECT_LOG4J_LOGGERS: org.apache.zookeeper=ERROR,org.I0Itec.zkclient=ERROR,org.reflections=ERROR
{{ end -}}

{{ if (datasource "config").ksqldb.enable }}
  ksqldb:
    image: confluentinc/cp-ksqldb-server:{{ (datasource "config").confluent.version }}
    hostname: {{ (datasource "config").ksqldb.name }}
    container_name: {{ (datasource "config").ksqldb.name }}
    depends_on:
    {{ range $i2, $e2 := (datasource "config").kafka -}}
        - {{ $e2.name}}
    {{ end -}}
    {{ if (datasource "config").sr.enable -}}
      - {{ (datasource "config").sr.name }}
    {{ end -}}
    {{ if (datasource "config").connect.enable -}}
      - {{ (datasource "config").connect.name }}
    {{ end -}}
    ports:
      - {{ (datasource "config").ksqldb.port }}:{{ (datasource "config").ksqldb.port }}
    environment:
      KSQL_CONFIG_DIR: "/etc/ksql"
      KSQL_BOOTSTRAP_SERVERS: {{ join $bs ","}}
      KSQL_HOST_NAME: {{ (datasource "config").ksqldb.name }}
      KSQL_LISTENERS: "http://0.0.0.0:{{ (datasource "config").ksqldb.port }}"
      KSQL_CACHE_MAX_BYTES_BUFFERING: 0
      {{ if (datasource "config").sr.enable -}}
      KSQL_KSQL_SCHEMA_REGISTRY_URL: "http://{{ (datasource "config").sr.name }}:{{ (datasource "config").sr.port }}"
      {{ end -}}
      KSQL_PRODUCER_INTERCEPTOR_CLASSES: "io.confluent.monitoring.clients.interceptor.MonitoringProducerInterceptor"
      KSQL_CONSUMER_INTERCEPTOR_CLASSES: "io.confluent.monitoring.clients.interceptor.MonitoringConsumerInterceptor"
      {{ if (datasource "config").connect.enable -}}
      KSQL_KSQL_CONNECT_URL: "http://{{ (datasource "config").connect.name }}:{{ (datasource "config").connect.port }}"
      {{ end -}}
      KSQL_KSQL_LOGGING_PROCESSING_TOPIC_REPLICATION_FACTOR: 1
      KSQL_KSQL_LOGGING_PROCESSING_TOPIC_AUTO_CREATE: 'true'
      KSQL_KSQL_LOGGING_PROCESSING_STREAM_AUTO_CREATE: 'true'
{{ end }}

{{ if (datasource "config").prometheus.enable }}
  prometheus:
    image: prom/prometheus
    container_name: prometheus
    depends_on:
    {{ range $i2, $e2 := (datasource "config").kafka -}}
        - {{ $e2.name}}
    {{ end -}}
    volumes:
      - $PWD/volumes/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - {{ (datasource "config").prometheus.port }}:{{ (datasource "config").prometheus.port }}
{{ end }}

{{ if (datasource "config").kafdrop.enable }}
  kafdrop:
    hostname: kafdrop
    container_name: kafdrop
    image: obsidiandynamics/kafdrop
    restart: "always"
    ports:
      - {{ (datasource "config").kafdrop.port }}:{{ (datasource "config").kafdrop.port }}
    environment:
      KAFKA_BROKERCONNECT: {{ join $bs "," }}
      {{- if (datasource "config").sr.enable }}
      CMD_ARGS: "--schemaregistry.connect=http://{{ (datasource "config").sr.name }}:{{ (datasource "config").sr.port }}"
      {{ end -}}
      JVM_OPTS: "-Xms16M -Xmx48M -Xss180K -XX:-TieredCompilation -XX:+UseStringDeduplication -noverify"
    depends_on:
      {{ range $i2, $e2 := (datasource "config").kafka -}}
        - {{ $e2.name}}
    {{ end -}}
{{ end }}