/**
 * HuggingFace API utilities for model downloads
 */

const HF_REPO = "argmaxinc/whisperkit-coreml";
const MODEL_BASE_URL = `https://huggingface.co/${HF_REPO}/resolve/main`;

export interface ModelInfo {
  id: string;
  name: string;
  size: string;
  sizeBytes: number;
  description: string;
}

// Fast model - the only one downloaded during installation
export const FAST_MODEL: ModelInfo = {
  id: "large-v3-v20240930_turbo_632MB",
  name: "Fast",
  size: "632 MB",
  sizeBytes: 632_000_000,
  description: "Fastest turbo model",
};

/**
 * Get list of files in a model directory (recursive)
 */
async function getModelFilesRecursive(path: string): Promise<string[]> {
  const url = `https://huggingface.co/api/models/${HF_REPO}/tree/main/${path}`;
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
 * Get all files for a specific model
 */
export async function getModelFiles(modelId: string): Promise<string[]> {
  return await getModelFilesRecursive(`openai_whisper-${modelId}`);
}

/**
 * Download a single file from HuggingFace
 */
export async function downloadModelFile(
  filePath: string,
  destPath: string,
): Promise<void> {
  const url = `${MODEL_BASE_URL}/${filePath}`;
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download ${filePath}: ${response.status}`);
  }

  const data = new Uint8Array(await response.arrayBuffer());
  await Deno.writeFile(destPath, data);
}

/**
 * Get the destination directory for models
 */
export function getModelDestDir(): string {
  const homeDir = Deno.env.get("HOME") || "~";
  return `${homeDir}/Library/Application Support/Koe/Models/models/argmaxinc/whisperkit-coreml`;
}

/**
 * Download a model with progress callback
 */
export async function downloadModel(
  model: ModelInfo,
  onProgress: (current: number, total: number, fileName: string) => void,
): Promise<void> {
  const baseDir = getModelDestDir();

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
