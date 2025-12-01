const express = require("express");
const cors = require("cors");
const routes = require("./routes");

const PORT = process.env.PORT || 3000;

const app = express();

app.use(cors());
app.use(express.json({ limit: "1mb" }));
app.use("/api", routes);

app.use((req, res) => {
  res.status(404).json({ message: "Rota não encontrada" });
});

app.use((error, req, res, next) => {
  console.error("Erro inesperado da API", error);
  res.status(500).json({ message: "Erro interno do servidor" });
});

app.listen(PORT, () => {
  console.log(`http://localhost:${PORT}`);
});
