import { html, css, LitElement, PropertyValues } from "lit";
import { customElement, property, state } from "lit/decorators.js";

@customElement("agent-console-snapshot-player")
export class AgentConsoleSnapshotPlayer extends LitElement {
  @property({ type: Array })
  items: { id: string; time: number }[] = [];

  @property({ type: Number })
  min: number = 0;

  @property({ type: Number })
  max: number = 0;

  @property({ type: Number })
  initialTime: number = 0;

  @state()
  private time: number = 0;
  @state()
  private isPlaying: boolean = false;
  @state()
  private isSeeking: boolean = false;
  private timer: any;

  static styles = css`
    .container {
      display: flex;
      align-items: center;
      flex-flow: row nowrap;
      height: 20px;
      gap: 4px;
      width: 100%;
    }

    .container > button {
      flex: none;
      margin: 0;
      outline: none;
      border: none;
      border-radius: 2px;
      width: 24px;
    }

    .track {
      display: flex;
      position: relative;
      border: 1px solid white;
      border-radius: 2px;
      height: 20px;
      flex: auto;
      box-sizing: border-box;
    }

    .track > div {
      position: absolute;
      top: 0;
      bottom: 0;
      width: 1px;
      background-color: white;
      pointer-events: none;
    }

    .track > div.currentTime {
      background-color: red;
      z-index: 1;
      wdith: 2px;
    }
    .track > div.currentTime::before {
      content: "";
      position: absolute;
      top: -1px;
      left: -2.5px;
      width: 6px;
      height: 0px;
      border-top: 1px solid red;
    }
    .track > div.currentTime::after {
      content: "";
      position: absolute;
      bottom: -1px;
      left: -2.5px;
      width: 6px;
      height: 0px;
      border-top: 1px solid red;
    }
  `;

  private handleClickReset() {
    this.time = this.initialTime;
    this.isPlaying = false;
    clearInterval(this.timer);
    this.fireTimeChange();
  }

  private handleClickScroll() {
    this.dispatchEvent(new CustomEvent("scrollToCurrent", { detail: {} }));
  }

  private prevId?: string;
  private fireTimeChange() {
    if (this.prevId === this.getCurrentItem()?.id) {
      return;
    }

    this.prevId = this.getCurrentItem()?.id;
    // console.log("timeChange", this.prevId);
    this.getCurrentItem()?.id;
    this.dispatchEvent(
      new CustomEvent("timeChange", {
        detail: { id: this.prevId }
      })
    );
  }

  private handleIsPlayingChange() {
    if (this.isPlaying) {
      this.timer = setInterval(() => {
        this.time += 50;
        this.fireTimeChange();
      }, 50);
    } else {
      clearInterval(this.timer);
      this.timer = null;
    }
  }

  private handleClickPlay() {
    this.isPlaying = !this.isPlaying;
    this.handleIsPlayingChange();
  }

  private updateTime(e: MouseEvent) {
    const rect = (e.target as HTMLElement).getBoundingClientRect();
    const x = e.clientX - rect.left;
    const pos = x / rect.width;
    this.time = Math.round(this.min + (this.max - this.min) * pos);
    this.fireTimeChange();
  }

  private getTimePosPercent(time: number) {
    // console.log(time, this.min, this.max);
    return `${((time - this.min) / (this.max - this.min)) * 100}%`;
  }

  private handleMouseDownTrack(e: MouseEvent) {
    this.isSeeking = true;
    clearInterval(this.timer);
    this.timer = null;

    this.updateTime(e);
  }

  private handleMouseMoveTrack(e: MouseEvent) {
    if (e.buttons === 1) {
      this.updateTime(e);
    }
  }

  private handleMouseUpTrack(e: MouseEvent) {
    this.isSeeking = false;
    this.handleIsPlayingChange();
  }

  render() {
    return html`<div class="container">
      <button @click=${this.handleClickPlay}>
        ${this.isPlaying && !this.isSeeking ? "❚❚" : "▶"}
      </button>
      <button @click=${this.handleClickReset}>↶</button>
      <button @click=${this.handleClickScroll}>📜</button>
      <div
        class="track"
        @mousedown=${this.handleMouseDownTrack}
        @mousemove=${this.handleMouseMoveTrack}
        @mouseup=${this.handleMouseUpTrack}
      >
        <div
          class="currentTime"
          style="left: ${this.getTimePosPercent(this.time)}"
        ></div>
        ${this.items.map(
          (item) =>
            html`<div style="left: ${this.getTimePosPercent(item.time)}"></div>`
        )}
      </div>
    </div>`;
  }

  connectedCallback(): void {
    super.connectedCallback();
    this.time = this.initialTime;
  }

  private getCurrentItem() {
    const i = this.items.findIndex((item) => this.time <= item.time);
    if (i > 0) {
      return this.items[i - 1];
    }
  }

  protected update(changedProperties: PropertyValues): void {
    super.update(changedProperties);
    if (changedProperties.has("initialTime")) {
      this.isPlaying = false;
      this.time = this.initialTime;
      if (this.timer) {
        clearInterval(this.timer);
        this.timer = null;
      }
    }
  }
}
