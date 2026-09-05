# RAG Test Corpus

이 문서 모음은 'Real-time Data Streaming & Analytics Architecture'를 주제로 RAG 검색/생성 시스템을 테스트하기 위한 샘플 코퍼스이다.

## 파일 구성
- 01_architecture_overview.md: 전체 아키텍처
- 02_kinesis.md: Kinesis Data Streams / Firehose
- 03_opensearch.md: OpenSearch
- 04_s3_glue_athena.md: S3 / Glue / Athena
- 05_scenarios.md: 운영 시나리오
- 06_design_decisions.md: 설계 의도와 서비스 간 관계
- 07_rag_test_questions.md: 평가 질문 20개
- 08_rag_expected_answers.md: 기대 답변

## 추천 테스트 방법
1. 01~06번 문서만 Vector DB에 임베딩한다.
2. 07번 질문을 검색/생성 테스트에 사용한다.
3. 08번 기대 답변을 정답셋으로 사용해 답변 품질을 비교한다.
4. 특히 9~12번 멀티홉 질문으로 여러 문서를 동시에 검색하는지 확인한다.
5. 13~16번 함정 질문으로 환각(hallucination) 여부를 확인한다.
