import { html, HTMLTemplateResult } from "lit";
import { jsonType, JsonType, ROW_HEIGHT } from "./model";

export function leafValueRenderer(
  value: JsonType,
  pathStr: string,
  options: {
    soundUrl: string;
    campaignPreviewUrl: string;
    controlPanelUrl: string;
    parentJson?: object;
  },
): HTMLTemplateResult {
  if (typeof value === "string") {
    if (
      URL.canParse(value) &&
      (/Global\/agents\/[0-9a-fA-F-]+\/avatar/i.test(value) ||
        /channelAccounts\.[0-9a-fA-F-]+\.avatarUrl$/i.test(pathStr) ||
        /.svg$/.test(value) ||
        /\/chatbots\/([^\/]+)\/avatar\?/.test(value))
    ) {
      return html`<a
          class="${value.includes("/avatar") ? "avatar" : ""}"
          href="${value}"
          target="_blank"
          ><img src="${value}" height="${ROW_HEIGHT}" /></a
        >${renderStringLink(value, value)}</span>`;
    } else if (URL.canParse(value)) {
      return renderStringLink(value, value);
    } else if (
      pathStr.endsWith(".agentConsoleLogoCodeSnippet") ||
      pathStr.endsWith(".controlPanelLogoCodeSnippet") ||
      (pathStr.endsWith(".htmlMessage") && value.length > 0)
    ) {
      const anchorName = `--preview-${pathStr}`;
      const id = `html-preview-${pathStr}`;
      return html`<span class="value string"
        ><button
          popovertarget="${id}"
          class="preview"
          style="anchor-name: ${anchorName};"
        ></button>
        <div
          id="${id}"
          class="html-preview ${pathStr.slice(pathStr.lastIndexOf(".") + 1)}"
          style="position-anchor: ${anchorName}; top: calc(anchor(bottom) + 4px); left: anchor(left); position-try-fallbacks: flip-block;"
          popover="auto"
          .innerHTML=${value}
        ></div>
        ${JSON.stringify(value)}</span
      >`;
    } else if (
      pathStr.endsWith(".notificationIcon") ||
      pathStr.endsWith(".ico") ||
      pathStr.endsWith(".faviconImage")
    ) {
      return html`<img
          class="image-preview"
          src="${`data:image/png;base64,${value}`}"
          height="${ROW_HEIGHT}"
        /><span class="value string">${JSON.stringify(value)}</span>`;
    } else if (
      /^#[0-9a-fA-F]{6}$/.test(value) ||
      /^#[0-9a-fA-F]{3}$/.test(value) ||
      /^rgba\(\s*[0-9]+,\s*[0-9]+,\s*[0-9]+,\s*[0-9.]+\s*\)$/.test(value) ||
      /^rgb\(\s*[0-9]+,\s*[0-9]+,\s*[0-9]+\s*\)$/.test(value)
    ) {
      // FIXME: add alpha
      return html`<span class="value string"
        ><input
          type="color"
          value="${value.startsWith("rgb")
            ? rgbaToHex(value)
            : expandHex(value)}"
        />
        ${JSON.stringify(value)}</span
      >`;
    } else if (
      (pathStr.startsWith("config.settings.sound") &&
        pathStr.endsWith(".id")) ||
      (pathStr.startsWith("config.preference") && pathStr.endsWith("SoundId"))
    ) {
      return html`<span class="value string"
        ><button
          class="play-sound"
          @click=${(e: MouseEvent) => {
            const button = e.currentTarget as HTMLButtonElement;
            button.classList.toggle("playing");

            const audio = document.createElement("audio");
            audio.src = options.soundUrl.replace("{soundId}", value);
            audio.onended = () => button.classList.remove("playing");
            audio.onerror = () => button.classList.remove("playing");
            audio.play();
          }}
        ></button
        >${JSON.stringify(value)}</span
      >`;
    } else if (
      pathStr.endsWith(".campaignId") ||
      /\.(codePlans|campaigns)\.[0-9]+\.id$/.test(pathStr)
    ) {
      // https://dash11.comm100.io/frontEnd/livechatpage/assets/livechat/previewpage/?campaignId=28f5d50f-45f8-401e-beac-283e2d67a7b3&siteId=10100000&lang=en
      return renderStringLink(
        options.campaignPreviewUrl.replace("{campaignId}", value),
        value,
      );
    } else if (
      /\.agents\.[0-9]+\.id$/.test(pathStr) ||
      pathStr.endsWith("agent.id")
    ) {
      // https://dash11.comm100.io/ui/10100000/global/people/agents/edit?agentid=ae99aa1e-eb77-4546-942f-2f590e4c7b5d
      return renderStringLink(
        `${options.controlPanelUrl}/global/people/agents/edit?agentId=${value}`,
        value,
      );
    } else if (/\.cannedMessages\.[0-9]+\.id$/.test(pathStr)) {
      const cannedMessage = options.parentJson as any;
      if (cannedMessage.isPrivate) {
        // https://dash11.comm100.io/ui/10100000/global/cannedmessages/manage/privatecannedmessage/edit?privatecannedmessageid=b82f49ca-afa2-4a10-b0d0-6e7207ea8ae1
        return renderStringLink(
          `${options.controlPanelUrl}/global/cannedmessages/manage/privatecannedmessage/edit?privatecannedmessageid=${value}`,
          value,
        );
      } else {
        // https://dash11.comm100.io/ui/10100000/global/cannedmessages/manage/publiccannedmessage/edit?publiccannedmessageid=eabe466b-2d01-46a8-b5bc-c2f1f6e8af06
        return renderStringLink(
          `${options.controlPanelUrl}/global/cannedmessages/manage/publiccannedmessage/edit?publiccannedmessageid=${value}`,
          value,
        );
      }
    }
  }

  return html`<span class="value ${jsonType(value)}"
    >${JSON.stringify(value)}</span
  >`;
}

function renderStringLink(url: string, text: string) {
  return html`<span class="value string"
    >"<a href="${url}" target="_blank">${text}</a>"</span
  >`;
}

function expandHex(hex: string) {
  if (hex.length === 4) {
    return `#${hex[1]}${hex[1]}${hex[2]}${hex[2]}${hex[3]}${hex[3]}`;
  }
  return hex;
}

function rgbaToHex(rgba: string) {
  const [r, g, b] = rgba.match(/\d+/g)!.map(Number);
  return `#${r.toString(16)}${g.toString(16)}${b.toString(16)}`;
}
