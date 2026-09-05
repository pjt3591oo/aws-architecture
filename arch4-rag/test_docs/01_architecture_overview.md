# 실시간 데이터 스트리밍 및 분석 아키텍처

## 개요
이 아키텍처는 데이터 생산자(Data Producers)가 생성한 이벤트를 Amazon Kinesis Data Streams로 수집하고, 이후 실시간 분석 경로와 장기 보관 및 SQL 분석 경로로 데이터를 분기하는 구조이다.

전체 흐름은 다음과 같다.

데이터 생산자 → Kinesis Data Streams → Kinesis Data Firehose → OpenSearch
데이터 생산자 → Kinesis Data Streams → Kinesis Data Firehose → S3
S3 → AWS Glue Database → AWS Glue Table → Amazon Athena → SQL 분석/리포트

## 목적
- 실시간 검색과 분석
- 원천 데이터의 안정적인 장기 보관
- SQL 기반의 배치성 분석
- 대시보드 및 리포팅 지원

## 핵심 특징
Kinesis Data Streams는 이벤트를 실시간으로 받아들이는 중심 스트림이다. 이후 Firehose를 이용해 OpenSearch와 S3로 각각 전달한다. OpenSearch는 실시간 검색과 분석에 사용하고, S3에는 Raw Data를 저장한다.

S3에 저장된 Raw Data는 AWS Glue를 통해 메타데이터를 등록하고, Athena가 SQL로 조회할 수 있도록 구성한다.

## 중요한 구분
OpenSearch는 실시간 검색/분석을 위한 저장소이고, S3는 원천 데이터의 장기 보관을 위한 저장소이다. Athena는 데이터를 직접 저장하는 서비스가 아니라 S3의 데이터를 SQL로 조회하는 쿼리 엔진이다.
