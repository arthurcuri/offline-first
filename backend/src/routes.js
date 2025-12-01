const { randomUUID } = require("crypto");
const express = require("express");
const store = require("./store");

const router = express.Router();

router.get("/health", (req, res) => {
  res.json({
    status: "ok",
    serverTime: Date.now(),
  });
});

router.get("/tasks", async (req, res) => {
  try {
    const userId = (req.query.userId || "user1").toString();
    const modifiedSince = parseNumber(req.query.modifiedSince);

    const tasks = await store.getTasksByFilter({
      userId,
      modifiedSince,
    });

    const serverTime = Date.now();
    const lastSync = await store.getLastTaskUpdate();

    res.json({
      success: true,
      tasks,
      lastSync,
      serverTime,
    });
  } catch (error) {
    console.error("Erro ao buscar tarefas", error);
    res.status(500).json({ message: "Erro ao buscar tarefas" });
  }
});

router.post("/tasks", async (req, res) => {
  try {
    const payload = req.body || {};
    const title = typeof payload.title === "string" ? payload.title.trim() : "";

    if (!title) {
      return res.status(400).json({ message: "Título é obrigatório" });
    }

    const now = Date.now();
    const task = {
      id: payload.id || randomUUID(),
      title,
      description:
        typeof payload.description === "string" ? payload.description : "",
      completed: parseBoolean(payload.completed),
      priority: payload.priority || "medium",
      userId: payload.userId || payload.user_id || "user1",
      createdAt: payload.createdAt || now,
      updatedAt: now,
      version: 1,
    };

    await store.upsertTask(task);
    res.status(201).json({ success: true, task });
  } catch (error) {
    console.error("Erro ao criar tarefa", error);
    res.status(500).json({ message: "Erro ao criar tarefa" });
  }
});

router.put("/tasks/:id", async (req, res) => {
  try {
    const existing = await store.getTaskById(req.params.id);

    if (!existing) {
      return res.status(404).json({ message: "Tarefa não encontrada" });
    }

    const clientVersion = parseNumber(req.body?.version);
    if (clientVersion === null) {
      return res.status(400).json({ message: "Versão obrigatória" });
    }

    if (clientVersion < existing.version) {
      return res.status(409).json({
        message: "Versão desatualizada",
        conflict: true,
        serverTask: existing,
      });
    }

    const now = Date.now();
    const updatedTask = {
      ...existing,
      title:
        typeof req.body.title === "string"
          ? req.body.title.trim()
          : existing.title,
      description:
        typeof req.body.description === "string"
          ? req.body.description
          : existing.description,
      completed: parseBoolean(req.body.completed, existing.completed),
      priority: req.body.priority || existing.priority,
      updatedAt: now,
      version: existing.version + 1,
    };

    await store.upsertTask(updatedTask);
    res.json({ success: true, task: updatedTask });
  } catch (error) {
    console.error("Erro ao atualizar tarefa", error);
    res.status(500).json({ message: "Erro ao atualizar tarefa" });
  }
});

router.delete("/tasks/:id", async (req, res) => {
  try {
    const existing = await store.getTaskById(req.params.id);

    if (!existing) {
      return res.json({ success: true });
    }

    const clientVersion = parseNumber(req.query.version);
    if (clientVersion !== null && clientVersion < existing.version) {
      return res.status(409).json({
        message: "Versão desatualizada",
        conflict: true,
        serverTask: existing,
      });
    }

    await store.deleteTask(req.params.id);
    res.json({ success: true });
  } catch (error) {
    console.error("Erro ao deletar tarefa", error);
    res.status(500).json({ message: "Erro ao deletar tarefa" });
  }
});

router.post("/sync/batch", async (req, res) => {
  const operations = Array.isArray(req.body?.operations)
    ? req.body.operations
    : [];
  const results = [];

  for (const operation of operations) {
    const normalizedType = normalizeOperationType(operation.type);
    try {
      switch (normalizedType) {
        case "create":
          results.push(await handleCreateOperation(operation));
          break;
        case "update":
          results.push(await handleUpdateOperation(operation));
          break;
        case "delete":
          results.push(await handleDeleteOperation(operation));
          break;
        default:
          results.push({
            id: operation.id,
            success: false,
            message: `Tipo de operação inválido: ${operation.type}`,
          });
      }
    } catch (error) {
      console.error("Erro ao processar operação em lote", error);
      results.push({
        id: operation.id,
        success: false,
        message: error.message || "Erro ao processar operação",
        conflict: error.conflict || false,
        serverTask: error.serverTask,
      });
    }
  }

  res.json({ results });
});

async function handleCreateOperation(operation) {
  const payload = operation.data || {};
  const now = Date.now();
  const task = {
    id: payload.id || operation.taskId || randomUUID(),
    title: typeof payload.title === "string" ? payload.title : "Sem título",
    description:
      typeof payload.description === "string" ? payload.description : "",
    completed: parseBoolean(payload.completed),
    priority: payload.priority || "medium",
    userId: payload.userId || payload.user_id || "user1",
    createdAt: payload.createdAt || now,
    updatedAt: now,
    version: 1,
  };

  await store.upsertTask(task);
  return { id: operation.id, success: true, task };
}

async function handleUpdateOperation(operation) {
  const existing = await store.getTaskById(operation.taskId);

  if (!existing) {
    throw new Error("Tarefa não encontrada para atualização");
  }

  const payload = operation.data || {};
  const clientVersion = parseNumber(payload.version);

  if (clientVersion !== null && clientVersion < existing.version) {
    const error = new Error("Versão desatualizada");
    error.conflict = true;
    error.serverTask = existing;
    throw error;
  }

  const now = Date.now();
  const updatedTask = {
    ...existing,
    title: typeof payload.title === "string" ? payload.title : existing.title,
    description:
      typeof payload.description === "string"
        ? payload.description
        : existing.description,
    completed: parseBoolean(payload.completed, existing.completed),
    priority: payload.priority || existing.priority,
    updatedAt: now,
    version: existing.version + 1,
  };

  await store.upsertTask(updatedTask);
  return { id: operation.id, success: true, task: updatedTask };
}

async function handleDeleteOperation(operation) {
  const existing = await store.getTaskById(operation.taskId);

  if (!existing) {
    return { id: operation.id, success: true };
  }

  const payload = operation.data || {};
  const clientVersion = parseNumber(payload.version);

  if (clientVersion !== null && clientVersion < existing.version) {
    const error = new Error("Versão desatualizada");
    error.conflict = true;
    error.serverTask = existing;
    throw error;
  }

  await store.deleteTask(operation.taskId);
  return { id: operation.id, success: true };
}

function parseBoolean(value, fallback = false) {
  if (typeof value === "boolean") return value;
  if (value === 1 || value === "1") return true;
  if (value === 0 || value === "0") return false;
  return fallback;
}

function parseNumber(value) {
  if (value === null || value === undefined || value === "") {
    return null;
  }

  const parsed = Number(value);
  return Number.isNaN(parsed) ? null : parsed;
}

function normalizeOperationType(type) {
  if (typeof type !== "string") return null;
  if (type.startsWith("OperationType.")) {
    return type.replace("OperationType.", "");
  }
  return type;
}

module.exports = router;
