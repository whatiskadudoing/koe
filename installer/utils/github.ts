/**
 * GitHub API utilities
 */

const REPO = "whatiskadudoing/koe";

export interface ReleaseInfo {
  version: string;
  tagName: string;
  publishedAt: string;
  downloadUrl: string;
}

/**
 * Get the latest release information
 */
export async function getLatestRelease(): Promise<ReleaseInfo> {
  const response = await fetch(
    `https://api.github.com/repos/${REPO}/releases/latest`,
  );

  if (!response.ok) {
    throw new Error(`Failed to fetch latest release: ${response.status}`);
  }

  const data = await response.json();

  return {
    version: data.tag_name,
    tagName: data.tag_name,
    publishedAt: data.published_at,
    downloadUrl:
      `https://github.com/${REPO}/releases/download/${data.tag_name}/Koe-macos-arm64.zip`,
  };
}

/**
 * Download a file from a URL to a temporary location
 */
export async function downloadFile(url: string): Promise<string> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status}`);
  }

  const tempDir = await Deno.makeTempDir();
  const fileName = url.split("/").pop() || "download";
  const filePath = `${tempDir}/${fileName}`;

  const data = new Uint8Array(await response.arrayBuffer());
  await Deno.writeFile(filePath, data);

  return filePath;
}

/**
 * Download with progress callback
 */
export async function downloadWithProgress(
  url: string,
  onProgress: (downloaded: number, total: number | null) => void,
): Promise<string> {
  const response = await fetch(url);

  if (!response.ok) {
    throw new Error(`Failed to download: ${response.status}`);
  }

  const contentLength = response.headers.get("content-length");
  const total = contentLength ? parseInt(contentLength) : null;

  const tempDir = await Deno.makeTempDir();
  const fileName = url.split("/").pop() || "download";
  const filePath = `${tempDir}/${fileName}`;

  const reader = response.body?.getReader();
  if (!reader) {
    throw new Error("No response body");
  }

  const chunks: Uint8Array[] = [];
  let downloaded = 0;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    chunks.push(value);
    downloaded += value.length;
    onProgress(downloaded, total);
  }

  // Combine chunks and write file
  const totalLength = chunks.reduce((acc, chunk) => acc + chunk.length, 0);
  const result = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }

  await Deno.writeFile(filePath, result);
  return filePath;
}
