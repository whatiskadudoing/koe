/**
 * App installation step
 */

const APP_NAME = "Koe.app";
const INSTALL_PATH = "/Applications";

/**
 * Extract and install app to /Applications
 */
export async function installApp(zipPath: string): Promise<void> {
  const tempDir = zipPath.replace("/Koe.zip", "");

  // Extract zip
  const unzip = new Deno.Command("unzip", {
    args: ["-o", zipPath, "-d", tempDir],
    stdout: "null",
    stderr: "null",
  });
  const unzipResult = await unzip.output();
  if (!unzipResult.success) {
    throw new Error("Failed to extract app");
  }

  // Remove existing app if present
  try {
    await Deno.remove(`${INSTALL_PATH}/${APP_NAME}`, { recursive: true });
  } catch {
    // App doesn't exist, that's fine
  }

  // Move to Applications
  const mv = new Deno.Command("mv", {
    args: [`${tempDir}/${APP_NAME}`, INSTALL_PATH],
  });
  const mvResult = await mv.output();
  if (!mvResult.success) {
    throw new Error("Failed to install app to /Applications");
  }

  // Clean up temp directory
  try {
    await Deno.remove(tempDir, { recursive: true });
  } catch {
    // Cleanup failure is non-fatal
  }
}

/**
 * Reset TCC permissions to clear stale entries
 */
export async function resetPermissions(): Promise<void> {
  const tccutil = new Deno.Command("tccutil", {
    args: ["reset", "Accessibility", "com.koe.voice"],
    stdout: "null",
    stderr: "null",
  });
  await tccutil.output();
  // Note: tccutil may return non-zero even on success
}

/**
 * Open the installed app
 */
export async function openApp(): Promise<void> {
  const open = new Deno.Command("open", {
    args: [`${INSTALL_PATH}/${APP_NAME}`],
  });
  await open.output();
}

/**
 * Get the path to the app binary
 */
export function getAppBinaryPath(): string {
  return `${INSTALL_PATH}/${APP_NAME}/Contents/MacOS/Koe`;
}
