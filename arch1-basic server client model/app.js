const http = require("http");
const { Client } = require("pg");

const port = 80;

const server = http.createServer(async (req, res) => {
  if (req.url === "/") {
    res.writeHead(200, { "Content-Type": "application/json" });
    return res.end(JSON.stringify({
      service: "ecs",
      version: "2.0.0",
      message: "hello from ecs v2"
    }));
  }

  if (req.url === "/db") {
    console.log(
`Connecting to RDS database at ${process.env.DB_HOST}:${process.env.DB_PORT} with user ${process.env.DB_USER}`
    )
    const client = new Client({
      host: process.env.DB_HOST,
      port: process.env.DB_PORT,
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME
    });

    try {
      await client.connect();

      const result = await client.query("SELECT 1 AS result");

      await client.end();

      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        ecs: "ok",
        rds: "ok",
        result: result.rows[0]
      }));
    } catch (error) {
      console.error(error);

      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        ecs: "ok",
        rds: "error",
        error: error.message
      }));
    }

    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(port, "0.0.0.0", () => {
  console.log(`server listening on ${port}`);
});