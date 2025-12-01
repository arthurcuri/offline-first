const fs = require("fs/promises");
const path = require("path");

const DATA_DIR = path.join(__dirname, "..", "data");
const DB_PATH = path.join(DATA_DIR, "db.json");

const defaultData = {
  tasks: [],
  lastTaskUpdate: 0,
};

async function readData() {
  try {
    console.log(`[LWW] [readData] Caminho absoluto: ${DB_PATH}`);
    const raw = await fs.readFile(DB_PATH, "utf-8");
    console.log(`[LWW] [readData] Conteúdo lido (até 500 chars): ${raw.slice(0, 500)}...`);
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === "ENOENT") {
      console.warn(`[LWW] [readData] Arquivo não encontrado, criando novo: ${DB_PATH}`);
      await ensureDataFile();
      return { ...defaultData };
    }
    console.error(`[LWW] [readData] Erro inesperado ao ler db.json:`, error);
    if (error.stack) console.error(error.stack);
    throw error;
  }
}

async function ensureDataFile() {
  await fs.mkdir(DATA_DIR, { recursive: true });
  await fs.writeFile(DB_PATH, JSON.stringify(defaultData, null, 2));
}

async function writeData(data) {
  await fs.mkdir(DATA_DIR, { recursive: true });
  await fs.writeFile(DB_PATH, JSON.stringify(data, null, 2));
  console.log(`[LWW] [writeData] db.json atualizado em ${new Date().toISOString()}`);
  console.log(`[LWW] [writeData] Caminho absoluto: ${DB_PATH}`);
  console.log(`[LWW] [writeData] Novo conteúdo (até 500 chars): ${JSON.stringify(data).slice(0, 500)}...`);
}

async function getAllTasks() {
  const data = await readData();
  return data.tasks;
}

async function getTaskById(id) {
  const tasks = await getAllTasks();
  return tasks.find((task) => task.id === id) || null;
}

async function upsertTask(task) {
  const data = await readData();
  const index = data.tasks.findIndex((t) => t.id === task.id);

  if (index === -1) {
    data.tasks.push(task);
  } else {
    const existing = data.tasks[index];
    // Só sobrescreve se version ou updatedAt do novo for maior
    if (
      (typeof task.version === 'number' && typeof existing.version === 'number' && task.version > existing.version) ||
      (typeof task.version === 'number' && typeof existing.version === 'number' && task.version === existing.version && task.updatedAt > existing.updatedAt)
    ) {
      data.tasks[index] = task;
    }
    // Senão, mantém o existente
  }

  data.lastTaskUpdate = Math.max(
    data.lastTaskUpdate,
    task.updatedAt || Date.now()
  );
  await writeData(data);
  return task;
}

async function deleteTask(id) {
  const data = await readData();
  const initialLength = data.tasks.length;
  data.tasks = data.tasks.filter((task) => task.id !== id);

  if (data.tasks.length !== initialLength) {
    await writeData(data);
    return true;
  }

  return false;
}

async function getTasksByFilter({ userId, modifiedSince }) {
  const tasks = await getAllTasks();
  return tasks.filter((task) => {
    if (userId && task.userId !== userId) {
      return false;
    }

    if (typeof modifiedSince === "number" && task.updatedAt <= modifiedSince) {
      return false;
    }

    return true;
  });
}

async function getLastTaskUpdate() {
  const data = await readData();
  return data.lastTaskUpdate || 0;
}

module.exports = {
  getAllTasks,
  getTaskById,
  upsertTask,
  deleteTask,
  getTasksByFilter,
  getLastTaskUpdate,
};
