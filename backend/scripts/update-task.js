#!/usr/bin/env node
/* eslint-disable no-console */

// npm run update-task -- --id ID_DA_TAREFA --title "Novo título" --description "..." --priority high --completed true

const DEFAULT_API = process.env.API_URL || "http://localhost:3000/api";

function parseArgs() {
  const args = {};
  const raw = process.argv.slice(2);

  for (let i = 0; i < raw.length; i++) {
    const key = raw[i];
    if (!key.startsWith("--")) {
      // Skip values already attached to a flag
      continue;
    }

    const value = raw[i + 1];
    if (!value || value.startsWith("--")) {
      args[key.slice(2)] = true;
      continue;
    }

    args[key.slice(2)] = value;
    i++;
  }

  return args;
}

function parseBoolean(value) {
  if (value === true || value === "true" || value === "1") return true;
  if (value === false || value === "false" || value === "0") return false;
  return null;
}

async function fetchJson(url, options) {
  const response = await fetch(url, options);
  if (!response.ok) {
    const body = await response.text();
    throw new Error(`${response.status} ${response.statusText}: ${body}`);
  }
  return response.json();
}

async function main() {
  const args = parseArgs();
  const apiUrl = args.api || DEFAULT_API;
  const userId = args.user || "user1";
  const desiredTaskId = args.id;

  const list = await fetchJson(`${apiUrl}/tasks?userId=${userId}`);
  if (!Array.isArray(list.tasks) || list.tasks.length === 0) {
    console.error("Nenhuma tarefa encontrada no servidor.");
    process.exit(1);
  }

  let task = list.tasks.find((t) => t.id === desiredTaskId);
  if (!task) {
    task = list.tasks[0];
    console.warn(
      desiredTaskId
        ? `⚠️ Tarefa ${desiredTaskId} não encontrada, usando ${task.id}`
        : `ℹ️ Nenhum id informado, usando ${task.id}`
    );
  }

  const payload = {
    version: task.version,
  };

  if (args.title) {
    payload.title = args.title;
  }

  if (args.description) {
    payload.description = args.description;
  }

  if (args.priority) {
    payload.priority = args.priority;
  }

  const completed = parseBoolean(args.completed);
  if (completed !== null) {
    payload.completed = completed;
  }

  if (
    !args.title &&
    !args.description &&
    !args.priority &&
    completed === null
  ) {
    payload.title = `${task.title} (editado no servidor)`;
  }

  const updated = await fetchJson(`${apiUrl}/tasks/${task.id}`, {
    method: "PUT",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });

  console.log("✅ Tarefa atualizada no servidor:");
  console.table({
    id: updated.task.id,
    title: updated.task.title,
    version: updated.task.version,
    completed: updated.task.completed,
  });
}

main().catch((error) => {
  console.error("❌ Erro ao atualizar tarefa:", error.message);
  process.exit(1);
});
