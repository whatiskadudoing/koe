/**
 * App download step
 */

import { getLatestRelease, downloadWithProgress } from "../utils/github.ts";

export interface DownloadResult {
  version: string;
  zipPath: string;
}

/**
 * Check for latest version
 */
export async function checkForUpdates(): Promise<string> {
  const release = await getLatestRelease();
  return release.version;
}

/**
 * Download the app with progress
 */
export async function downloadApp(
  version: string,
  onProgress?: (downloaded: number, total: number | null) => void
): Promise<string> {
  const url = `https://github.com/whatiskadudoing/koe/releases/download/${version}/Koe-macos-arm64.zip`;

  if (onProgress) {
    return await downloadWithProgress(url, onProgress);
  }

  // Simple download without progress
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to download app: ${response.status}`);
  }

  const tempDir = await Deno.makeTempDir();
  const zipPath = `${tempDir}/Koe.zip`;
  const data = new Uint8Array(await response.arrayBuffer());
  await Deno.writeFile(zipPath, data);

  return zipPath;
}
