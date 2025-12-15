import { Controller } from "@hotwired/stimulus";
import { createConsumer } from "@rails/actioncable";

export default class extends Controller {
  static targets = [
    "sidebar",
    "overlay",
    "contentArea",
    "connectionStatus",
    "currentTime",
    "statValue",
    "livePositionsTable",
    "paperPositionsTable",
    "tradingModeBtn",
    "sidebarTitle",
    "sidebarCollapseBtn",
  ];

  static values = {
    channel: String,
  };

  connect() {
    this.updateTime();
    this.timeInterval = setInterval(() => this.updateTime(), 1000);

    // Restore sidebar collapse state from localStorage
    this.restoreSidebarState();

    // Handle window resize
    this.handleResize = () => this.onWindowResize();
    window.addEventListener("resize", this.handleResize);

    // Connect to ActionCable
    if (this.channelValue) {
      this.connectToChannel();
    }
  }

  disconnect() {
    if (this.timeInterval) {
      clearInterval(this.timeInterval);
    }

    if (this.handleResize) {
      window.removeEventListener("resize", this.handleResize);
    }

    if (this.subscription) {
      this.subscription.unsubscribe();
    }

    if (this.consumer) {
      this.consumer.disconnect();
    }
  }

  toggleSidebar() {
    this.sidebarTarget.classList.toggle("active");
    this.overlayTarget.classList.toggle("active");
  }

  closeSidebar() {
    this.sidebarTarget.classList.remove("active");
    this.overlayTarget.classList.remove("active");
  }

  toggleSidebarCollapse() {
    const isCollapsed = this.sidebarTarget.classList.toggle("collapsed");
    this.saveSidebarState(isCollapsed);
    this.updateCollapseButtonIcon(isCollapsed);
  }

  restoreSidebarState() {
    // Only restore on desktop (md and up)
    if (window.innerWidth < 768) return;

    const savedState = localStorage.getItem("sidebarCollapsed");
    if (savedState === "true") {
      this.sidebarTarget.classList.add("collapsed");
      this.updateCollapseButtonIcon(true);
    }
  }

  saveSidebarState(isCollapsed) {
    localStorage.setItem("sidebarCollapsed", isCollapsed.toString());
  }

  updateCollapseButtonIcon(isCollapsed) {
    if (!this.hasSidebarCollapseBtnTarget) return;

    const icon = this.sidebarCollapseBtnTarget.querySelector("i");
    if (icon) {
      icon.className = isCollapsed
        ? "bi bi-chevron-right"
        : "bi bi-chevron-left";
    }
  }

  onWindowResize() {
    // On mobile, ensure sidebar is not collapsed (use slide-in/out behavior)
    if (window.innerWidth < 768) {
      this.sidebarTarget.classList.remove("collapsed");
      this.updateCollapseButtonIcon(false);
    } else {
      // On desktop, restore saved state
      this.restoreSidebarState();
    }
  }

  handleScreenerStream(data) {
    // Handle real-time screener updates via ActionCable
    if (data.type === "screener_ltp_update") {
      // Update single LTP
      this.updateScreenerLtp(data.symbol, data.instrument_id, data.ltp);
    } else if (data.type === "screener_ltp_batch_update") {
      // Update multiple LTPs at once
      if (data.updates && Array.isArray(data.updates)) {
        data.updates.forEach((update) => {
          this.updateScreenerLtp(update.symbol, update.instrument_id, update.ltp);
        });
      }
    } else if (data.type === "screener_progress") {
      // Update progress display if on screener page
      const statusMessage = document.querySelector(
        '[data-screener-target="statusMessage"]'
      );
      if (statusMessage && data.progress) {
        const progress = data.progress;
        const pct =
          progress.total > 0
            ? Math.round((progress.processed / progress.total) * 100)
            : 0;
        const elapsed = progress.elapsed || 0;
        const remaining = progress.remaining || 0;
        const candidateCount = progress.candidates || 0;

        statusMessage.textContent =
          `Processing: ${progress.processed}/${progress.total} (${pct}%) - ` +
          `${progress.analyzed} analyzed, ${candidateCount} candidates found - ` +
          `${elapsed}s elapsed${
            remaining > 0 ? `, ~${remaining}s remaining` : ""
          }`;
      }
    } else if (data.type === "screener_record_added") {
      // Add/update individual record in table for live updates
      this.handleScreenerRecordAdded(data);
    } else if (data.type === "ai_evaluation_added") {
      // Update record with AI evaluation results
      this.handleAIEvaluationAdded(data);
    } else if (data.type === "ai_evaluation_filtered") {
      // Show that candidate was filtered out by AI
      this.handleAIEvaluationFiltered(data);
    } else if (data.type === "ai_evaluation_complete") {
      // Show AI evaluation phase completion
      this.handleAIEvaluationComplete(data);
    } else if (data.type === "screener_partial_results") {
      // Update progressive results display
      if (window.updateProgressiveResults && data.candidates) {
        window.updateProgressiveResults(data.candidates, data.progress || {});
      }
    } else if (data.type === "screener_complete") {
      // Reload page to show final results
      const statusMessage = document.querySelector(
        '[data-screener-target="statusMessage"]'
      );
      if (statusMessage) {
        statusMessage.textContent = `Results ready! Found ${data.candidate_count} candidates. Refreshing...`;
      }
      setTimeout(() => {
        window.location.reload();
      }, 2000);
    }
  }

  updateTime() {
    const now = new Date();
    const timeString = now.toLocaleTimeString("en-US", {
      hour12: false,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
    });

    if (this.hasCurrentTimeTarget) {
      this.currentTimeTarget.textContent = timeString;
    }
  }

  connectToChannel() {
    this.consumer = createConsumer();

    this.subscription = this.consumer.subscriptions.create(
      { channel: this.channelValue },
      {
        connected: () => {
          console.log("Connected to ActionCable");
          this.updateConnectionStatus(true);
        },

        disconnected: () => {
          console.log("Disconnected from ActionCable");
          this.updateConnectionStatus(false);
        },

        received: (data) => {
          this.handleUpdate(data);
          // Handle screener streaming updates
          if (
            data.type === "screener_progress" ||
            data.type === "screener_partial_results" ||
            data.type === "screener_complete" ||
            data.type === "screener_record_added" ||
            data.type === "ai_evaluation_added" ||
            data.type === "ai_evaluation_filtered" ||
            data.type === "ai_evaluation_complete" ||
            data.type === "screener_ltp_update" ||
            data.type === "screener_ltp_batch_update"
          ) {
            this.handleScreenerStream(data);
          }
        },
      }
    );
  }

  updateConnectionStatus(connected) {
    if (!this.hasConnectionStatusTarget) return;

    const indicator =
      this.connectionStatusTarget.querySelector(".status-indicator");
    const text = this.connectionStatusTarget.querySelector(".status-text");

    if (indicator) {
      indicator.classList.toggle("connected", connected);
      indicator.classList.toggle("disconnected", !connected);
    }

    if (text) {
      text.textContent = connected ? "Connected" : "Disconnected";
    }
  }

  handleUpdate(data) {
    // Handle different types of updates
    switch (data.type) {
      case "position_update":
        this.updatePosition(data.position);
        break;
      case "signal_update":
        this.updateSignal(data.signal);
        break;
      case "order_update":
        this.updateOrder(data.order);
        break;
      case "stats_update":
        this.updateStats(data.stats);
        break;
      case "screener_update":
        this.handleScreenerUpdate(data);
        break;
      default:
        console.log("Unknown update type:", data.type);
    }
  }

  handleScreenerUpdate(data) {
    // Show notification that screener completed
    if (data.screener_type && data.candidate_count !== undefined) {
      const message = `${data.screener_type} screener completed: Found ${data.candidate_count} candidates`;
      console.log(message);

      // Reload page after a short delay to show results
      setTimeout(() => {
        if (window.location.pathname.includes("screener")) {
          window.location.reload();
        }
      }, 2000);
    }
  }

  updatePosition(position) {
    // Find and update position row in tables
    const row = document.querySelector(`tr[data-position-id="${position.id}"]`);
    if (!row) return;

    // Update current price and P&L
    const currentPriceCell = row.querySelector("td:nth-child(5)");
    const pnlCell = row.querySelector("td:nth-child(6)");

    if (currentPriceCell) {
      currentPriceCell.textContent = `₹${parseFloat(
        position.current_price
      ).toFixed(2)}`;
    }

    if (pnlCell) {
      const pnl = parseFloat(position.unrealized_pnl);
      pnlCell.textContent = `₹${pnl.toFixed(0)}`;
      pnlCell.className = pnl >= 0 ? "text-success" : "text-danger";
    }

    // Add flash animation
    row.classList.add("updated");
    setTimeout(() => row.classList.remove("updated"), 1000);
  }

  updateSignal(signal) {
    // Update signal in the list
    const signalElement = document.querySelector(
      `div[data-signal-id="${signal.id}"]`
    );
    if (!signalElement) return;

    // Update execution status
    const badge = signalElement.querySelector(".badge");
    if (badge && signal.executed) {
      badge.className = "badge bg-success";
      badge.textContent = "Executed";
    }

    signalElement.classList.add("updated");
    setTimeout(() => signalElement.classList.remove("updated"), 1000);
  }

  updateOrder(order) {
    // Update order in the list
    const orderElement = document.querySelector(
      `div[data-order-id="${order.id}"]`
    );
    if (!orderElement) return;

    // Update status badge
    const badge = orderElement.querySelector(".badge");
    if (badge) {
      const statusClasses = {
        executed: "bg-success",
        rejected: "bg-danger",
        cancelled: "bg-secondary",
        pending: "bg-warning",
      };
      badge.className = `badge ${
        statusClasses[order.status] || "bg-secondary"
      }`;
      badge.textContent =
        order.status.charAt(0).toUpperCase() + order.status.slice(1);
    }

    orderElement.classList.add("updated");
    setTimeout(() => orderElement.classList.remove("updated"), 1000);
  }

  updateStats(stats) {
    // Update stat cards
    Object.keys(stats).forEach((statKey) => {
      const statElement = document.querySelector(`[data-stat="${statKey}"]`);
      if (statElement) {
        statElement.textContent = stats[statKey];
      }
    });
  }

  toggleTradingMode(event) {
    event.preventDefault();
    const button = event.currentTarget;
    const currentMode = button.dataset.mode;
    const newMode = currentMode === "live" ? "paper" : "live";

    // Disable button during request
    button.disabled = true;

    // Make AJAX request to toggle mode
    const csrfToken = document.querySelector(
      'meta[name="csrf-token"]'
    )?.content;
    if (!csrfToken) {
      console.error("CSRF token not found");
      button.disabled = false;
      return;
    }

    fetch("/dashboard/toggle_mode", {
      method: "POST",
      headers: {
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')
          .content,
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ mode: newMode }),
    })
      .then((response) => response.json())
      .then((data) => {
        // Update button appearance
        button.dataset.mode = newMode;
        button.classList.remove("btn-danger", "btn-info");
        button.classList.add(newMode === "live" ? "btn-danger" : "btn-info");

        // Update icon and text
        const icon = button.querySelector("i");
        const text = button.querySelector(".mode-text");
        if (icon) {
          icon.className = `bi bi-${
            newMode === "live" ? "lightning-charge" : "file-earmark-text"
          }`;
        }
        if (text) {
          text.textContent = newMode.toUpperCase();
        }

        // Reload page to show updated data
        window.location.reload();
      })
      .catch((error) => {
        console.error("Error toggling trading mode:", error);
        button.disabled = false;
        alert("Failed to toggle trading mode. Please try again.");
      });
  }

  handleScreenerRecordAdded(data) {
    if (!data.record || !data.record.symbol) return;

    const record = data.record;
    const tbody = document.querySelector(
      'tbody[data-screener-results="true"][data-screener-type="swing"]'
    );

    if (!tbody) {
      // Table might not be rendered yet, skip
      return;
    }

    // Check if row already exists
    const existingRow = tbody.querySelector(
      `tr[data-screener-symbol="${record.symbol}"]`
    );

    if (existingRow) {
      // Update existing row
      this.updateScreenerRow(existingRow, record, tbody);
    } else {
      // Add new row
      const newRow = this.createScreenerRow(record);
      tbody.appendChild(newRow);
    }

    // Sort rows by score and update ranks
    this.sortScreenerRows(tbody);

    // Update progress if available
    if (data.progress) {
      this.updateScreenerProgress(data.progress);
    }
  }

  createScreenerRow(record) {
    const row = document.createElement("tr");
    row.setAttribute("data-screener-symbol", record.symbol);
    row.setAttribute("data-screener-instrument-id", record.instrument_id);

    const indicators = record.indicators || {};
    const score = record.score || 0;
    const baseScore = record.base_score || 0;
    const mtfScore = record.mtf_score || 0;
    const rsi = indicators.rsi;
    const adx = indicators.adx;
    const supertrend = indicators.supertrend;
    const ema20 = indicators.ema20;
    const ema50 = indicators.ema50;
    const macd = indicators.macd;
    const latestClose = indicators.latest_close || 0;
    const aiScore = record.ai_score;
    const aiConfidence = record.ai_confidence;

    // Score badge color
    const scoreClass =
      score >= 70 ? "success" : score >= 50 ? "warning" : "secondary";

    // RSI badge color
    const rsiClass = rsi > 70 ? "danger" : rsi < 30 ? "success" : "info";

    // ADX badge color
    const adxClass = adx > 25 ? "success" : "secondary";

    // Supertrend badge
    const stDirection = supertrend?.direction || "";
    const stClass = stDirection === "bullish" ? "success" : "danger";

    // EMA trend
    const emaTrend =
      ema20 && ema50 ? (ema20 > ema50 ? "BULL" : "BEAR") : "";
    const emaClass = ema20 > ema50 ? "success" : "danger";

    // MACD
    const macdLine = macd?.[0];
    const signalLine = macd?.[1];
    const macdTrend =
      macdLine && signalLine ? (macdLine > signalLine ? "BULL" : "BEAR") : "";
    const macdClass = macdLine > signalLine ? "success" : "secondary";

    row.innerHTML = `
      <td><strong>#<span class="rank-number">1</span></strong></td>
      <td><strong>${record.symbol}</strong></td>
      <td>
        <span class="badge bg-${scoreClass}">
          ${score.toFixed(1)}
        </span>
      </td>
      <td>${baseScore.toFixed(1)}</td>
      <td>${mtfScore.toFixed(1)}</td>
      <td>₹${latestClose.toFixed(2)}</td>
      <td>
        ${
          rsi
            ? `<span class="badge bg-${rsiClass}">${rsi.toFixed(1)}</span>`
            : '<span class="text-muted">-</span>'
        }
      </td>
      <td>
        ${
          adx
            ? `<span class="badge bg-${adxClass}">${adx.toFixed(1)}</span>`
            : '<span class="text-muted">-</span>'
        }
      </td>
      <td>
        ${
          supertrend
            ? `<span class="badge bg-${stClass}">${stDirection.toUpperCase()}</span>`
            : '<span class="text-muted">-</span>'
        }
      </td>
      <td>
        ${
          emaTrend
            ? `<span class="badge bg-${emaClass}">${emaTrend}</span>`
            : '<span class="text-muted">-</span>'
        }
      </td>
      <td>
        ${
          macdTrend
            ? `<span class="badge bg-${macdClass}">${macdTrend}</span>`
            : '<span class="text-muted">-</span>'
        }
      </td>
      ${
        aiScore || aiConfidence
          ? `
        <td>
          ${
            aiScore
              ? `<span class="badge bg-${
                  aiScore >= 80 ? "success" : aiScore >= 60 ? "warning" : "secondary"
                }">${aiScore.toFixed(1)}</span>`
              : '<span class="text-muted">-</span>'
          }
        </td>
        <td>
          ${
            aiConfidence
              ? `<span class="badge bg-info">${aiConfidence.toFixed(1)}</span>`
              : '<span class="text-muted">-</span>'
          }
        </td>
        `
          : ""
      }
    `;

    return row;
  }

  updateScreenerRow(row, record, tbody) {
    // Update the row with new data (similar to createScreenerRow but update existing)
    const newRow = this.createScreenerRow(record);
    row.replaceWith(newRow);
  }

  sortScreenerRows(tbody) {
    const rows = Array.from(tbody.querySelectorAll("tr[data-screener-symbol]"));
    rows.sort((a, b) => {
      // Extract score from the third column (Score column)
      const scoreCellA = a.querySelector("td:nth-child(3)");
      const scoreCellB = b.querySelector("td:nth-child(3)");
      
      const scoreA = parseFloat(
        scoreCellA?.querySelector(".badge")?.textContent?.trim() ||
        scoreCellA?.textContent?.trim() ||
        "0"
      ) || 0;
      
      const scoreB = parseFloat(
        scoreCellB?.querySelector(".badge")?.textContent?.trim() ||
        scoreCellB?.textContent?.trim() ||
        "0"
      ) || 0;
      
      return scoreB - scoreA; // Descending order
    });

    // Re-append sorted rows and update ranks
    rows.forEach((row, index) => {
      tbody.appendChild(row);
      const rankCell = row.querySelector(".rank-number");
      if (rankCell) {
        rankCell.textContent = index + 1;
      } else {
        const rankTd = row.querySelector("td:first-child");
        if (rankTd) {
          rankTd.innerHTML = `<strong>#${index + 1}</strong>`;
        }
      }
    });
  }

  updateScreenerProgress(progress) {
    const statusMessage = document.querySelector(
      '[data-screener-target="statusMessage"]'
    );
    if (statusMessage && progress) {
      const elapsed = progress.elapsed || 0;
      const remaining = progress.remaining || 0;
      statusMessage.textContent = `Processing: ${progress.processed || 0}/${
        progress.total || 0
      } instruments, ${progress.analyzed || 0} analyzed, ${
        progress.candidates || 0
      } candidates found - ${elapsed.toFixed(1)}s elapsed${
        remaining > 0 ? `, ~${remaining.toFixed(0)}s remaining` : ""
      }`;
    }
  }

  handleAIEvaluationAdded(data) {
    if (!data.record || !data.record.symbol) return;

    const record = data.record;
    const tbody = document.querySelector(
      'tbody[data-screener-results="true"][data-screener-type="swing"]'
    );

    if (!tbody) return;

    // Find existing row and update with AI data
    const existingRow = tbody.querySelector(
      `tr[data-screener-symbol="${record.symbol}"]`
    );

    if (existingRow) {
      // Update AI columns if they exist, or add them
      this.updateRowWithAIData(existingRow, record);
    } else {
      // Row doesn't exist yet, create it (shouldn't happen, but handle gracefully)
      const newRow = this.createScreenerRow(record);
      tbody.appendChild(newRow);
    }

    // Update progress
    if (data.progress) {
      this.updateAIEvaluationProgress(data.progress);
    }
  }

  updateRowWithAIData(row, record) {
    // Check if AI columns exist
    const cells = row.querySelectorAll("td");
    const hasAIColumns = row.querySelector("td:nth-child(11)") !== null; // AI Score column

    if (hasAIColumns) {
      // Update existing AI columns
      const aiScoreCell = row.querySelector("td:nth-child(11)");
      const aiConfidenceCell = row.querySelector("td:nth-child(12)");

      if (aiScoreCell && record.ai_confidence) {
        const score = record.ai_confidence * 10; // Convert 0-10 to 0-100
        const scoreClass =
          score >= 80 ? "success" : score >= 60 ? "warning" : "secondary";
        aiScoreCell.innerHTML = `<span class="badge bg-${scoreClass}">${score.toFixed(1)}</span>`;
      }

      if (aiConfidenceCell && record.ai_confidence) {
        aiConfidenceCell.innerHTML = `<span class="badge bg-info">${record.ai_confidence.toFixed(1)}</span>`;
      }
    } else {
      // Add AI columns if they don't exist
      // This requires checking the table header first
      const thead = row.closest("table")?.querySelector("thead");
      if (thead) {
        const headerRow = thead.querySelector("tr");
        // Check if AI headers exist
        const hasAIHeaders = headerRow.querySelector("th:nth-child(11)") !== null;

        if (!hasAIHeaders) {
          // Add AI headers
          const aiScoreHeader = document.createElement("th");
          aiScoreHeader.textContent = "AI Score";
          const aiConfidenceHeader = document.createElement("th");
          aiConfidenceHeader.textContent = "AI Confidence";
          headerRow.appendChild(aiScoreHeader);
          headerRow.appendChild(aiConfidenceHeader);
        }

        // Add AI data cells
        const aiScoreCell = document.createElement("td");
        const aiConfidenceCell = document.createElement("td");

        if (record.ai_confidence) {
          const score = record.ai_confidence * 10;
          const scoreClass =
            score >= 80 ? "success" : score >= 60 ? "warning" : "secondary";
          aiScoreCell.innerHTML = `<span class="badge bg-${scoreClass}">${score.toFixed(1)}</span>`;
          aiConfidenceCell.innerHTML = `<span class="badge bg-info">${record.ai_confidence.toFixed(1)}</span>`;
        } else {
          aiScoreCell.innerHTML = '<span class="text-muted">-</span>';
          aiConfidenceCell.innerHTML = '<span class="text-muted">-</span>';
        }

        row.appendChild(aiScoreCell);
        row.appendChild(aiConfidenceCell);
      }
    }
  }

  handleAIEvaluationFiltered(data) {
    // Show that a candidate was filtered out
    if (data.progress) {
      this.updateAIEvaluationProgress(data.progress);
    }
    // Could add visual indicator or log
    console.log(
      `AI filtered out ${data.symbol}: ${data.reason} (confidence: ${data.confidence})`
    );
  }

  handleAIEvaluationComplete(data) {
    // Show completion message
    const statusMessage = document.querySelector(
      '[data-screener-target="statusMessage"]'
    );
    if (statusMessage && data.progress) {
      statusMessage.textContent = `AI Evaluation complete: ${data.candidate_count} candidates approved (${data.progress.duration}s)`;
    }
  }

  updateAIEvaluationProgress(progress) {
    const statusMessage = document.querySelector(
      '[data-screener-target="statusMessage"]'
    );
    if (statusMessage && progress) {
      const elapsed = progress.elapsed || 0;
      statusMessage.textContent = `AI Evaluation: ${progress.processed || 0}/${
        progress.total || 0
      } evaluated, ${progress.evaluated || 0} approved - ${elapsed.toFixed(1)}s elapsed`;
    }
  }

  updateScreenerLtp(symbol, instrumentId, ltp) {
    if (!symbol || !ltp) return;

    // Find all rows with this symbol (could be in multiple tables/tabs)
    const rows = document.querySelectorAll(
      `tr[data-screener-symbol="${symbol}"], tr[data-screener-instrument-id="${instrumentId}"]`
    );

    rows.forEach((row) => {
      // Find the price cell (usually contains ₹ symbol)
      const priceCells = row.querySelectorAll("td");
      priceCells.forEach((cell) => {
        const cellText = cell.textContent.trim();
        // Check if this cell contains a price (starts with ₹)
        if (cellText.startsWith("₹")) {
          const oldPrice = parseFloat(cellText.replace("₹", "").replace(/,/g, ""));
          const newPrice = parseFloat(ltp);

          // Update the price
          cell.textContent = `₹${newPrice.toFixed(2)}`;

          // Add visual indicator for price change
          if (oldPrice && oldPrice !== newPrice) {
            const changeClass = newPrice > oldPrice ? "price-up" : "price-down";
            cell.classList.add(changeClass);
            setTimeout(() => {
              cell.classList.remove(changeClass);
            }, 1000);
          }

          // Update data attribute if present
          if (row.hasAttribute("data-price")) {
            row.setAttribute("data-price", newPrice.toFixed(2));
          }
        }
      });

      // Add flash animation to indicate update
      row.classList.add("ltp-updated");
      setTimeout(() => {
        row.classList.remove("ltp-updated");
      }, 500);
    });
  }
}
