import { html, HTMLTemplateResult } from "lit";
import { jsonType, JsonType, ROW_HEIGHT } from "./model";
import PermissionItems from "./T_Global_PermissionItem.json";

export function leafValueRenderer(
  value: JsonType,
  pathStr: string,
  options: {
    soundUrl: string;
    campaignPreviewUrl: string;
    controlPanelUrl: string;
    partnerPortalUrl: string;
    siteId: number;
    partnerId: number;
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
      pathStr.endsWith("agent.id") ||
      /\.agentIds\.[0-9]+$/.test(pathStr) ||
      /\.segments\.[0-9]+\.alertToIds\.[0-9]+$/.test(pathStr)
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
    } else if (/\.customAways\.[0-9]+\.id$/.test(pathStr)) {
      // https://dash11.comm100.io/ui/10100000/global/people/customawaystatus/edit?agentawaystatusid=b2cc04bc-a562-eb11-aac4-0219204b659b
      return renderStringLink(
        `${options.controlPanelUrl}/global/people/customawaystatus/edit?agentawaystatusid=${value}`,
        value,
      );
    } else if (/\.customVariables\.[0-9]+\.id$/.test(pathStr)) {
      // https://dash11.comm100.io/ui/10100000/app/CustomVariables/edit?customvariableid=a8ac795c-1870-4626-b224-394f0c3a51e4
      return renderStringLink(
        `${options.controlPanelUrl}/app/CustomVariables/edit?customvariableid=${value}`,
        value,
      );
    } else if (
      /\.departments\.[0-9]+\.id$/.test(pathStr) ||
      /\.departmentId$/.test(pathStr)
    ) {
      // https://dash11.comm100.io/ui/10100000/global/people/departments/edit?departmentid=51f01e39-94ac-484f-8eb8-33422a585d97
      return renderStringLink(
        `${options.controlPanelUrl}/global/people/departments/edit?departmentid=${value}`,
        value,
      );
    } else if (/\.segments\.[0-9]+\.id$/.test(pathStr)) {
      // https://dash11.comm100.io/ui/10100000/livechat/settings/segmentation/edit?segmentid=7f8c4778-2126-4ff3-a4ba-9089cf24159c
      return renderStringLink(
        `${options.controlPanelUrl}/livechat/settings/segmentation/edit?segmentid=${value}`,
        value,
      );
    } else if (
      /\.skills\.[0-9]+\.id$/.test(pathStr) ||
      /\.skillId$/.test(pathStr)
    ) {
      // https://dash11.comm100.io/ui/10100000/global/people/skills/edit?skillid=ec79aeb2-d88d-46ac-b391-9d2828992224
      return renderStringLink(
        `${options.controlPanelUrl}/global/people/skills/edit?skillid=${value}`,
        value,
      );
    } else if (/\.contactFields\.[0-9]+\.id$/.test(pathStr)) {
      // https://dash11.comm100.io/ui/10100000/contactmanagement/fields/edit?custompageid=34a07697-a7d0-4035-80b6-6111857ec875
      return renderStringLink(
        `${options.controlPanelUrl}/contactmanagement/fields/edit?custompageid=${value}`,
        value,
      );
    } else if (
      /\.chats\.[a-fA-F0-9-]+\.id$/.test(pathStr) ||
      /chats\.list\.\w+\.\d+/.test(pathStr) ||
      /\bloadDatas\.chats-[a-fA-F0-9-]+\.data\.\d+\.guid$/.test(pathStr)
    ) {
      // https://livechat3dash.testing.comm100dev.io/ui/10008/livechat/history/chats/transcriptdetail/?chatId=5979afa9-c9b4-47ae-8e3d-de180b6fa3d0
      return renderStringLink(
        `${options.controlPanelUrl}/livechat/history/chats/transcriptdetail/?chatId=${value}`,
        value,
      );
    } else if (
      /\bloadDatas\.chats-[a-fA-F0-9-]+\.data\.\d+\.visitorId$/.test(pathStr)
    ) {
      // https://livechat3dash.testing.comm100dev.io/ui/10008/livechat/history/Chats/historyInfo/?visitorId=9ab92b2c-b916-40cb-a383-8c7bcc807761
      return renderStringLink(
        `${options.controlPanelUrl}/livechat/history/Chats/historyInfo/?visitorId=${value}`,
        value,
      );
    } else if (
      pathStr.endsWith(".botId") ||
      pathStr.endsWith(".chatbotId") ||
      /\.bots\.[0-9]+\.id$/.test(pathStr)
    ) {
      // https://livechat3dash.testing.comm100dev.io/ui/10008/ai/aiagent/?scopingchatbotid=0853bb85-e394-42f7-9910-05e7fc0f2482
      return renderStringLink(
        `${options.controlPanelUrl}/ai/aiagent/?scopingchatbotid=${value}`,
        value,
      );
    } else if (pathStr.endsWith(".KBId")) {
      // https://livechat3dash.testing.comm100dev.io/ui/10008/kb/knowledgebases/?scopingknowledgebaseid=c53b0f30-f1fc-4ef1-8df4-35d24a6bb5e4
      return renderStringLink(
        `${options.controlPanelUrl}/kb/knowledgebases/?scopingknowledgebaseid=${value}`,
        value,
      );
    }
  } else if (typeof value === "number") {
    if (pathStr.endsWith(".partnerId")) {
      // https://livechat3partner.testing.comm100dev.io/ui/10000/partnersite/site/detail/?partnerid=10000&siteid=10000
      return renderNumberLink(
        `${options.partnerPortalUrl}/partnersite/site/detail/?partnerid=${value}&siteid=${options.siteId}`,
        value,
      );
    } else if (
      /\bloadDatas\.chats-[a-fA-F0-9-]+\.data\.\d+\.id$/.test(pathStr)
    ) {
      // https://livechat3dash.testing.comm100dev.io/ui/10008/livechat/history/chats/transcriptdetail/?chatId=1234
      return renderNumberLink(
        `${options.controlPanelUrl}/livechat/history/chats/transcriptdetail/?chatId=${value}`,
        value,
      );
    } else if (/\.permissions\.[0-9]+$/.test(pathStr)) {
      const permission = PermissionItems.find(
        (permission) => permission.Id === value,
      );
      if (permission) {
        return html`<span
          class="value number"
          title="${permission.Description.replace(/<br\s*\/>/g, "\n")
            .replace(/<span[^>]+>\s*(.*?)\s*<\/span>/g, "$1")
            .replace(/<b>\s*(.*?)\s*<\/b>/g, "$1")}"
          >${value}
          <span class="permission"
            >(${permission.ModuleId} - ${permission.Name})</span
          ></span
        >`;
      } else {
        return html`<span class="value number">${value}</span>`;
      }
    }
  }

  return html`<span class="value ${jsonType(value)}"
    >${JSON.stringify(value)}</span
  >`;
}

function renderStringLink(url: string, text: string) {
  if (url.includes("00000000-0000-0000-0000-000000000000")) {
    return html`<span class="value string">"${text}"</span>`;
  }

  return html`<span class="value string"
    >"<a href="${url}" target="_blank">${text}</a>"</span
  >`;
}

function renderNumberLink(url: string, text: number) {
  return html`<span class="value number"
    ><a href="${url}" target="_blank">${text}</a></span
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
