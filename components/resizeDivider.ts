import { LitElement, html, css } from "lit";
import {
  customElement,
  eventOptions,
  property,
  query,
  state,
} from "lit/decorators.js";

@customElement("resize-divider")
export class ResizeDivier extends LitElement {
  render() {
    return html`<div
      id="resize-divider"
      @mousedown=${this._handleMouseDown}
    ></div>`;
  }

  static styles = css`
    #resize-divider {
      width: 100%;
      height: 100%;
    }
  `;

  @property({ type: String })
  direction: "horizontal" | "vertical" = "vertical";

  @query("#resize-divider")
  element!: HTMLDivElement;

  @state()
  private _isResizing: boolean = false;

  @eventOptions({ passive: true })
  private _handleMouseDown(e: MouseEvent) {
    e.stopPropagation();

    this._isResizing = true;

    let x = e.clientX;
    let y = e.clientY;

    const overlay = document.createElement("div");
    overlay.id = "resize-overlay";
    overlay.style.cssText = `z-index: 1000; position: fixed; top: 0; left: 0; right: 0; bottom: 0; cursor: ${
      this.direction === "horizontal" ? "row-resize" : "col-resize"
    };`;
    document.body.append(overlay);

    overlay.addEventListener("mousemove", (e) => {
      e.stopPropagation();
      try {
        const dx = e.clientX - x;
        const dy = e.clientY - y;

        // if no button is pressed, stop resizing
        if (e.buttons === 0) {
          this._dispatchResizeEvent(e, 0, 0, true);
          overlay.remove();
          return;
        }
        this._dispatchResizeEvent(e, dx, dy, false);
      } finally {
        x = e.clientX;
        y = e.clientY;
      }
    });

    overlay.addEventListener("mouseup", (e) => {
      try {
        e.stopPropagation();
        const dx = e.clientX - x;
        const dy = e.clientY - y;
        this._dispatchResizeEvent(e, dx, dy, true);
        overlay.remove();
      } finally {
        x = e.clientX;
        y = e.clientY;
      }
    });
  }

  private _dispatchResizeEvent(
    _e: MouseEvent,
    dx: number,
    dy: number,
    isFinished: boolean,
  ) {
    if (!this._isResizing) return;
    this.dispatchEvent(
      new CustomEvent("resize", {
        composed: true,
        bubbles: true,
        detail: {
          dx,
          dy,
          isFinished: isFinished,
        },
      }),
    );
  }
}
