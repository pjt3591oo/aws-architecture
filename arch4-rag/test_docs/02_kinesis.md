# Amazon Kinesis 구성 요소

## Kinesis Data Streams
Kinesis Data Streams는 애플리케이션이나 장비에서 발생하는 이벤트를 실시간으로 수집하는 스트리밍 서비스이다.

이 예제에서는 `kinesis-analytics-demo-stream`이라는 이름의 스트림을 사용한다고 가정한다.

Data Producers에는 웹 애플리케이션, 모바일 애플리케이션, 서버, IoT 장비 등이 포함될 수 있다.

## Kinesis Data Firehose
Kinesis Data Firehose는 스트리밍 데이터를 대상으로 전달하는 데 사용된다.

이 아키텍처에서는 두 개의 Firehose 전달 경로가 존재한다.

1. `kinesis-analytics-demo-to-os`
   - 목적지: Amazon OpenSearch
   - 용도: 실시간 검색 및 분석

2. `kinesis-analytics-demo-to-s3`
   - 목적지: Amazon S3
   - 용도: Raw Data 저장 및 후속 분석

## Data Streams와 Firehose의 역할 차이
Data Streams는 이벤트를 받아들이는 실시간 스트림의 중심 역할을 한다.
Firehose는 스트리밍 데이터를 지정된 목적지로 전달하는 역할을 한다.

따라서 두 서비스를 동일한 역할의 서비스로 보면 안 된다.
