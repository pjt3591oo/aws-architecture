"use strict";

/**
 * S3 -> (ObjectCreated event) -> ingest handler
 * 텍스트 문서를 청킹 -> 임베딩(로컬 llama.cpp) -> S3 Vectors 인덱스에 저장
 *
 * 필요한 fetch: Node.js 18+ (Lambda nodejs20.x)는 전역 fetch를 기본 제공합니다.
 */
const { S3Client, GetObjectCommand } = require("@aws-sdk/client-s3");
const { S3VectorsClient, PutVectorsCommand } = require("@aws-sdk/client-s3vectors");

const AWS_ENDPOINT_URL = process.env.AWS_ENDPOINT_URL;
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "rag-vectors";
const INDEX_NAME = process.env.INDEX_NAME || "docs-index";
const EMBEDDING_URL = process.env.EMBEDDING_URL || "http://host.docker.internal:8081/v1/embeddings";
const CHUNK_SIZE = parseInt(process.env.CHUNK_SIZE || "800", 10);
const CHUNK_OVERLAP = parseInt(process.env.CHUNK_OVERLAP || "100", 10);

const s3 = new S3Client({ endpoint: AWS_ENDPOINT_URL, forcePathStyle: true });
const s3vectors = new S3VectorsClient({ endpoint: AWS_ENDPOINT_URL });

function chunkText(text, size = CHUNK_SIZE, overlap = CHUNK_OVERLAP) {
  const chunks = [];
  let start = 0;
  const n = text.length;
  while (start < n) {
    const end = Math.min(start + size, n);
    chunks.push(text.slice(start, end));
    if (end === n) break;
    start = end - overlap;
  }
  return chunks;
}

async function embed(text) {
  const res = await fetch(EMBEDDING_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ input: text, model: "bartowski/Qwen_Qwen3-0.6B-GGUF:Q4_K_M" }),
  });
  if (!res.ok) {
    throw new Error(`embedding request failed: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return data.data[0].embedding;
}

function randomSuffix() {
  return Math.random().toString(16).slice(2, 10);
}

exports.handler = async (event) => {
  const processed = [];

  for (const record of event.Records || []) {
    const bucket = record.s3.bucket.name;
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, " "));

    const obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
    const body = await obj.Body.transformToString("utf-8");

    const chunks = chunkText(body);
    const vectors = [];

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const embedding = await embed(chunk);
      vectors.push({
        key: `${key}#chunk-${i}-${randomSuffix()}`,
        data: { float32: embedding },
        metadata: {
          source_key: key,
          source_bucket: bucket,
          chunk_index: i,
          text: chunk.slice(0, 2000),
        },
      });
    }

    // S3 Vectors는 한 번에 최대 500개 벡터까지 put 가능 -> 배치 처리
    for (let i = 0; i < vectors.length; i += 500) {
      const batch = vectors.slice(i, i + 500);
      await s3vectors.send(
        new PutVectorsCommand({
          vectorBucketName: VECTOR_BUCKET,
          indexName: INDEX_NAME,
          vectors: batch,
        })
      );
    }

    processed.push({ key, chunks: chunks.length });
  }

  return { statusCode: 200, body: JSON.stringify({ processed }) };
};
