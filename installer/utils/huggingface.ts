/**
 * HuggingFace API utilities for model downloads
 */

const WHISPER_REPO = "argmaxinc/whisperkit-coreml";
const WHISPER_BASE_URL = `https://huggingface.co/${WHISPER_REPO}/resolve/main`;

const QWEN_REPO = "Qwen/Qwen2.5-3B-Instruct-GGUF";
const QWEN_FILE = "qwen2.5-3b-instruct-q4_k_m.gguf";
const QWEN_URL = `https://huggingface.co/${QWEN_REPO}/resolve/main/${QWEN_FILE}`;

export interface ModelInfo {
  id: string;
  name: string;
  size: string;
  sizeBytes: number;
  description: string;
}

// Turbo model - primary transcription model downloaded during installation
export const TURBO_MODEL: ModelInfo = {
  id: "large-v3_turbo_954MB",
  name: "Turbo",
  size: "954 MB",
  sizeBytes: 954_000_000,
  description: "Fast & accurate transcription",
};

// Qwen model - AI text refinement
export const QWEN_MODEL: ModelInfo = {
  id: "qwen2.5-3b-instruct-q4_k_m",
  name: "Qwen 2.5 3B",
  size: "~2 GB",
  sizeBytes: 2_000_000_000,
  description: "AI text refinement",
};

/**
 * Get list of files in a model directory (recursive)
 */
async function getModelFilesRecursive(path: string): Promise<string[]> {
  const url = `https://huggingface.co/api/models/${WHISPER_REPO}/tree/main/${path}`;
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to get file list for ${path}: ${response.status}`);
  }

  const items = await response.json();
  const allFiles: string[] = [];

  for (const item of items) {
    if (item.type === "file") {
      allFiles.push(item.path);
    } else if (item.type === "directory") {
      const subFiles = await getModelFilesRecursive(item.path);
      allFiles.push(...subFiles);
    }
  }

  return allFiles;
}

/**
 * Get all files for a specific WhisperKit model
 */
export async function getModelFiles(modelId: string): Promise<string[]> {
  return await getModelFilesRecursive(`openai_whisper-${modelId}`);
}

/**
 * Download a single file from a URL with progress
 */
export async function downloadFile(
  url: string,
  destPath: string,
  onProgress?: (downloaded: number, total: number) => void,
): Promise<void> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status}`);
  }

  const contentLength = response.headers.get("content-length");
  const total = contentLength ? parseInt(contentLength, 10) : 0;

  if (!response.body) {
    throw new Error("No response body");
  }

  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let downloaded = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    chunks.push(value);
    downloaded += value.length;

    if (onProgress && total > 0) {
      onProgress(downloaded, total);
    }
  }

  // Combine chunks and write to file
  const totalLength = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  await Deno.writeFile(destPath, result);
}

/**
 * Download a single file from HuggingFace (simple version)
 */
export async function downloadModelFile(
  filePath: string,
  destPath: string,
): Promise<void> {
  const url = `${WHISPER_BASE_URL}/${filePath}`;
  await downloadFile(url, destPath);
}

/**
 * Get the destination directory for WhisperKit models
 */
export function getWhisperModelDir(): string {
  const homeDir = Deno.env.get("HOME") || "~";
  return `${homeDir}/Library/Application Support/Koe/Models/models/argmaxinc/whisperkit-coreml`;
}

/**
 * Get the destination directory for Koe models
 */
export function getKoeModelDir(): string {
  const homeDir = Deno.env.get("HOME") || "~";
  return `${homeDir}/Library/Application Support/Koe/Models`;
}

/**
 * Download a WhisperKit model with progress callback
 */
export async function downloadWhisperModel(
  model: ModelInfo,
  onProgress: (current: number, total: number, fileName: string) => void,
): Promise<void> {
  const baseDir = getWhisperModelDir();

  // Create base directory
  await Deno.mkdir(baseDir, { recursive: true });

  // Get list of files to download
  const files = await getModelFiles(model.id);
  const totalFiles = files.length;

  for (let i = 0; i < files.length; i++) {
    const filePath = files[i];
    const destPath = `${baseDir}/${filePath}`;
    const fileName = filePath.split("/").pop() || filePath;

    // Create parent directories if needed
    const parentDir = destPath.substring(0, destPath.lastIndexOf("/"));
    await Deno.mkdir(parentDir, { recursive: true });

    // Report progress
    onProgress(i + 1, totalFiles, fileName);

    // Download file
    await downloadModelFile(filePath, destPath);
  }
}

/**
 * Download Qwen model with progress callback
 */
export async function downloadQwenModel(
  onProgress: (percent: number) => void,
): Promise<void> {
  const destDir = getKoeModelDir();
  await Deno.mkdir(destDir, { recursive: true });

  const destPath = `${destDir}/${QWEN_FILE}`;

  // Check if already downloaded
  try {
    const stat = await Deno.stat(destPath);
    if (stat.size > 1_900_000_000) {
      // ~2GB, close enough
      onProgress(100);
      return;
    }
  } catch {
    // File doesn't exist, proceed with download
  }

  await downloadFile(QWEN_URL, destPath, (downloaded, total) => {
    const percent = Math.round((downloaded / total) * 100);
    onProgress(percent);
  });
}

// Legacy export for backwards compatibility
export const FAST_MODEL = TURBO_MODEL;
export function getModelDestDir(): string {
  return getWhisperModelDir();
}
export const downloadModel = downloadWhisperModel;
