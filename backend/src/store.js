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
    const raw = await fs.readFile(DB_PATH, "utf-8");
    return JSON.parse(raw);
  } catch (error) {
    if (error.code === "ENOENT") {
      await ensureDataFile();
      return { ...defaultData };
    }
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
    data.tasks[index] = task;
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
