# S3, AWS Glue, Amazon Athena 분석 경로

## S3 Raw Data
Kinesis Data Firehose를 통해 전달된 원천 이벤트 데이터는 Amazon S3에 저장한다.

예시 경로:
`s3://kinesis-analytics-demo-0000000000/raw/`

S3는 Raw Data의 장기 보관과 데이터 레이크의 기반 저장소 역할을 한다.

## AWS Glue Database
AWS Glue Database는 데이터 자체를 저장하는 데이터베이스 서버가 아니다.

Glue Data Catalog에서 테이블을 논리적으로 그룹화하고 메타데이터를 관리하기 위한 단위이다.

예시 이름:
`kinesis-analytics-demo_db`

## AWS Glue Table
Glue Table은 S3에 저장된 데이터의 구조와 위치 등의 메타데이터를 정의한다.

예시 테이블 이름:
`kinesis-analytics-demo_events`

## Amazon Athena
Amazon Athena는 S3에 저장된 데이터를 SQL로 조회할 수 있는 서버리스 쿼리 서비스이다.

예를 들어 다음과 같은 분석을 수행할 수 있다.

- 이벤트 유형별 개수
- 일자별 이벤트 수
- 평균 거래 금액
- 특정 사용자 활동 분석

Athena는 일반적으로 Glue Data Catalog의 테이블 메타데이터를 이용해 S3 데이터를 SQL로 조회한다.

## 전체 관계
S3는 실제 Raw Data를 저장한다.
Glue Database와 Glue Table은 데이터의 메타데이터를 관리한다.
Athena는 이 메타데이터를 이용해 S3 데이터를 SQL로 조회한다.
