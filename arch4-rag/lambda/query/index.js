"use strict";

/**
 * API Gateway (POST /query, body: {"question": "..."}) -> query handler
 * 질문 임베딩 -> S3 Vectors 유사도 검색(top-k) -> 컨텍스트 구성 -> llama.cpp 채팅 완성 -> 답변 반환
 */
const { S3VectorsClient, QueryVectorsCommand } = require("@aws-sdk/client-s3vectors");

const AWS_ENDPOINT_URL = process.env.AWS_ENDPOINT_URL;
const VECTOR_BUCKET = process.env.VECTOR_BUCKET || "rag-vectors";
const INDEX_NAME = process.env.INDEX_NAME || "docs-index";
const EMBEDDING_URL = process.env.EMBEDDING_URL || "http://host.docker.internal:8081/v1/embeddings";
const CHAT_URL = process.env.CHAT_URL || "http://host.docker.internal:8082/v1/chat/completions";
const TOP_K = parseInt(process.env.TOP_K || "4", 10);

const s3vectors = new S3VectorsClient({ endpoint: AWS_ENDPOINT_URL });

async function embed(text) {
  const res = await fetch(EMBEDDING_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ input: text, model: "embedding-model" }),
  });
  if (!res.ok) {
    throw new Error(`embedding request failed: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return data.data[0].embedding;
}

async function search(queryVector, topK = TOP_K) {
  const resp = await s3vectors.send(
    new QueryVectorsCommand({
      vectorBucketName: VECTOR_BUCKET,
      indexName: INDEX_NAME,
      queryVector: { float32: queryVector },
      topK,
      returnMetadata: true,
      returnDistance: true,
    })
  );
  return resp.vectors || [];
}

function buildContext(matches) {
  return matches
    .map((m) => {
      const meta = m.metadata || {};
      return `[출처: ${meta.source_key || "unknown"}]\n${meta.text || ""}`;
    })
    .join("\n\n---\n\n");
}

async function askLlm(question, context) {
  const systemPrompt =
    "당신은 주어진 컨텍스트만 근거로 답하는 도우미입니다. 컨텍스트에 답이 없으면 모른다고 답하세요.";
  const userPrompt = `컨텍스트:\n${context}\n\n질문: ${question}`;

  const res = await fetch(CHAT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "bartowski/Qwen_Qwen3-0.6B-GGUF:Q4_K_M",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.2,
      max_tokens: 512,
    }),
  });
  if (!res.ok) {
    throw new Error(`chat request failed: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  return data.choices[0].message.content;
}

function response(statusCode, payload) {
  return {
    statusCode,
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  };
}

exports.handler = async (event) => {
  let body = {};
  try {
    body = JSON.parse(event.body || "{}");
  } catch (e) {
    body = {};
  }

  const question = (body.question || "").trim();
  if (!question) {
    return response(400, { error: "question 필드가 필요합니다." });
  }

  const queryVector = await embed(question);
  const matches = await search(queryVector);
  const context = buildContext(matches);
  const answer = await askLlm(question, context);

  return response(200, {
    question,
    answer,
    sources: matches.map((m) => (m.metadata || {}).source_key),
  });
};
