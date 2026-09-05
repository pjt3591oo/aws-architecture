# RAG 평가용 기대 답변

1. Kinesis Data Streams는 이벤트를 실시간으로 수집하는 중심 스트림이다.
2. OpenSearch는 실시간 검색과 분석에 사용된다.
3. 예시 경로는 `s3://kinesis-analytics-demo-0000000000/raw/`이다.
4. Athena는 데이터를 저장하지 않는다. S3에 저장된 데이터를 SQL로 조회한다.
5. Glue Database는 테이블을 논리적으로 그룹화하고, Glue Table은 특정 데이터셋의 스키마와 위치 등의 메타데이터를 정의한다.

6. OpenSearch는 실시간 검색/분석에 적합하고, S3는 Raw Data의 장기 보관과 대규모 분석 기반에 적합하다.
7. Data Streams는 이벤트를 수집하는 스트림이고, Firehose는 스트리밍 데이터를 OpenSearch나 S3 같은 목적지로 전달한다.
8. Glue Table은 데이터 구조와 위치를 설명하는 메타데이터이고, Athena는 그 메타데이터를 활용해 S3 데이터를 SQL로 조회하는 쿼리 엔진이다.

9. 데이터 생산자 → Kinesis Data Streams → Kinesis Data Firehose → S3 → Glue Database/Glue Table → Athena 순서로 연결된다.
10. 이벤트는 Kinesis Data Streams에서 수집된 뒤 Firehose를 통해 OpenSearch와 S3로 각각 전달될 수 있다. OpenSearch는 실시간 검색에, S3는 장기 보관 및 Athena 분석에 사용된다.
11. S3, AWS Glue Data Catalog(Glue Database/Table), Amazon Athena가 사용된다.
12. 실시간 검색과 장기 보관/대규모 SQL 분석은 요구사항과 저장 방식이 다르므로 OpenSearch와 S3 기반 경로를 분리한다.

13. 아니다. Athena는 쿼리 엔진이다.
14. 아니다. Glue Database는 메타데이터 카탈로그상의 논리적 그룹이다.
15. 아니다. 이 아키텍처에서는 S3가 Raw Data의 장기 보관에 사용된다.
16. 아니다. Kinesis Data Streams는 이벤트 스트림이며 SQL 쿼리 엔진이 아니다.

17. OpenSearch 경로가 적절하다.
18. S3 → Glue → Athena 경로가 적절하다.
19. S3에 Raw Data를 보관하는 것이 적절하다.
20. Glue Table 등의 메타데이터를 등록하여 S3 데이터의 구조와 위치를 Athena가 인식할 수 있도록 해야 한다.
