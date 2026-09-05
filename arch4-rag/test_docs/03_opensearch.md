# Amazon OpenSearch 분석 경로

## 역할
Amazon OpenSearch는 실시간 검색과 분석을 위한 저장 및 검색 시스템으로 사용한다.

이 아키텍처에서는 Kinesis Data Streams에서 들어온 데이터가 Kinesis Data Firehose를 거쳐 OpenSearch로 전달된다.

## 데이터
OpenSearch에는 `events`라는 인덱스를 사용할 수 있다.

예를 들어 이벤트 데이터에 다음과 같은 필드가 있다고 가정한다.

- event_id
- event_type
- user_id
- timestamp
- amount
- source

## 사용 사례
- 최근 이벤트 검색
- 특정 사용자 이벤트 조회
- 이벤트 유형별 집계
- 실시간 대시보드
- 운영 상황 모니터링

## S3와의 차이
OpenSearch는 검색과 실시간 분석에 적합하다.
S3는 대규모 Raw Data를 저렴하게 장기간 보관하는 데 적합하다.

따라서 OpenSearch를 S3의 완전한 대체재로 생각하지 않는다.
