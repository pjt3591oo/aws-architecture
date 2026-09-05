# 설계 결정 사항과 주의점

## 왜 OpenSearch와 S3를 함께 사용하는가?
두 저장소의 목적이 다르기 때문이다.

OpenSearch는 빠른 검색과 실시간 분석을 제공하는 데 초점을 둔다.
S3는 원천 데이터를 장기간 보관하고 다양한 분석 작업의 기반으로 사용하는 데 초점을 둔다.

## 왜 Firehose를 사용하는가?
Kinesis Data Streams로 수집한 스트리밍 데이터를 OpenSearch 또는 S3 같은 목적지로 전달하기 위해 사용한다.

## Glue Database와 Glue Table의 차이
Glue Database는 테이블들을 논리적으로 묶는 카탈로그상의 그룹이다.
Glue Table은 특정 데이터셋의 스키마와 위치 등 메타데이터를 정의한다.

## Athena와 Glue의 관계
Glue가 데이터 자체를 변환하거나 저장하는 데이터베이스라고 생각하면 안 된다.
이 구성에서 Glue는 주로 데이터 카탈로그와 메타데이터를 제공하고, Athena가 그 메타데이터를 활용해 S3 데이터를 SQL로 조회한다.

## 실시간 경로와 분석 경로
실시간 경로:
Kinesis Data Streams → Firehose → OpenSearch

분석/보관 경로:
Kinesis Data Streams → Firehose → S3 → Glue → Athena

두 경로는 동일한 이벤트 스트림에서 시작하지만 최종 목적과 사용 방식이 다르다.
