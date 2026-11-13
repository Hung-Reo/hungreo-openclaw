export type TelegramBotCommand = {
  command: string
  description: string
}

export type TelegramCommandScope = {
  type: 'all_private_chats'
}

export type SetMyCommandsApi = {
  setMyCommands: (
    commands: TelegramBotCommand[],
    other?: { scope?: TelegramCommandScope },
  ) => Promise<unknown>
}

export const GEMINI_BOT_COMMANDS: readonly TelegramBotCommand[] = [
  { command: 'status', description: 'Xem model, phiên & ngân sách token' },
  { command: 'handover', description: 'Tóm tắt handover & mở phiên mới' },
  { command: 'x_brief', description: 'Chạy thử Bản tin X Đối Chứng ngay' },
  { command: 'model', description: 'Xem hoặc đổi model Gemini' },
  { command: 'reset_thread', description: 'Xoá trắng context phiên hiện tại' },
  { command: 'start', description: 'Giới thiệu @hungreo_gemini_bot' },
]

/**
 * Registers `@hungreo_gemini_bot` slash commands for private DM chats on Telegram startup.
 */
export async function registerGeminiBotCommands(
  api: SetMyCommandsApi,
  onError?: (err: unknown) => void,
): Promise<boolean> {
  try {
    await api.setMyCommands(
      GEMINI_BOT_COMMANDS.map(item => ({ ...item })),
      { scope: { type: 'all_private_chats' } },
    )
    return true
  } catch (err) {
    onError?.(err)
    return false
  }
}
