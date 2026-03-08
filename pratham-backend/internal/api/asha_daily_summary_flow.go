package api

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"net/http"
	"sort"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	awsconfig "github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/bedrockruntime"
	bedrocktypes "github.com/aws/aws-sdk-go-v2/service/bedrockruntime/types"
	"github.com/prathamcare/backend/internal/models"
)

const aiSummaryFallbackWarning = "AI summary unavailable; showing rule-based summary"

type ashaRankedAppointment struct {
	AppointmentID string   `json:"appointment_id"`
	PatientID     string   `json:"patient_id"`
	PatientName   string   `json:"patient_name"`
	PriorityScore int      `json:"priority_score"`
	PriorityLevel string   `json:"priority_level"`
	Reasons       []string `json:"reasons"`
}

type ashaDaySummaryTotals struct {
	Appointments int `json:"appointments"`
	Critical     int `json:"critical"`
	High         int `json:"high"`
	Medium       int `json:"medium"`
	Low          int `json:"low"`
}

type ashaDaySummaryNarrative struct {
	SummaryTextShort string   `json:"summary_text_short"`
	SummaryTextFull  string   `json:"summary_text_full"`
	TopFocusPoints   []string `json:"top_focus_points"`
	RiskNotes        []string `json:"risk_notes"`
}

func (h *Handler) handleASHADaySummary(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	params := req.QueryStringParameters
	tzName := strings.TrimSpace(params["tz"])
	if tzName == "" {
		tzName = "Asia/Kolkata"
	}
	loc, err := time.LoadLocation(tzName)
	if err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid tz")
	}

	dateStr := strings.TrimSpace(params["date"])
	if dateStr == "" {
		dateStr = time.Now().In(loc).Format("2006-01-02")
	}
	targetDate, err := time.ParseInLocation("2006-01-02", dateStr, loc)
	if err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "date must be in YYYY-MM-DD format")
	}

	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 2*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	readCtx, cancelRead := context.WithTimeout(ctx, 6*time.Second)
	signals, lErr := h.deps.Aurora.ListASHADailyAppointmentSignals(readCtx, ownerID, targetDate.Format("2006-01-02"), tzName)
	cancelRead()
	if lErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to build day summary")
	}

	ranked, totals := rankASHADailyAppointments(signals, time.Now().In(loc))
	ruleNarrative := buildRuleBasedASHANarrative(ranked, totals)
	narrative := ruleNarrative
	warnings := make([]string, 0, 1)

	if len(ranked) > 0 {
		aiCtx, cancelAI := context.WithTimeout(ctx, 8*time.Second)
		aiNarrative, aiErr := h.generateASHADaySummaryNarrative(aiCtx, targetDate, tzName, totals, ranked)
		cancelAI()
		if aiErr != nil {
			warnings = append(warnings, aiSummaryFallbackWarning)
		} else {
			narrative = aiNarrative
		}
	}

	return h.json(http.StatusOK, map[string]any{
		"date":                targetDate.Format("2006-01-02"),
		"totals":              totals,
		"summary_text_short":  narrative.SummaryTextShort,
		"summary_text_full":   narrative.SummaryTextFull,
		"top_focus_points":    narrative.TopFocusPoints,
		"ranked_appointments": ranked,
		"risk_notes":          narrative.RiskNotes,
		"warnings":            warnings,
	})
}

func rankASHADailyAppointments(signals []models.ASHADailyAppointmentSignal, now time.Time) ([]ashaRankedAppointment, ashaDaySummaryTotals) {
	ranked := make([]ashaRankedAppointment, 0, len(signals))
	totals := ashaDaySummaryTotals{Appointments: len(signals)}

	for _, sig := range signals {
		score := 18
		reasons := make([]string, 0, 6)
		addReason := func(reason string) {
			reason = strings.TrimSpace(reason)
			if reason == "" {
				return
			}
			for _, existing := range reasons {
				if strings.EqualFold(existing, reason) {
					return
				}
			}
			reasons = append(reasons, reason)
		}

		switch strings.ToLower(strings.TrimSpace(sig.Status)) {
		case "in_progress":
			score += 45
			addReason("Visit already in progress and needs immediate closure")
		case "accepted":
			score += 30
			addReason("Patient has confirmed this visit")
		case "assigned":
			score += 22
		case "requested":
			score += 16
		case "completed":
			score -= 35
			addReason("Already completed today")
		}

		switch strings.ToLower(strings.TrimSpace(sig.ReasonCode)) {
		case "maternal_newborn_follow_up":
			score += 36
			addReason("Maternal/newborn follow-up has elevated clinical risk")
		case "referral_support":
			score += 34
			addReason("Referral support may require same-day escalation")
		case "home_visit_follow_up":
			score += 24
			addReason("Follow-up visit requires continuity of care")
		case "immunization_mobilization":
			score += 18
		case "community_follow_up":
			score += 14
		case "family_planning_counseling":
			score += 10
		case "general_health_check":
			score += 8
		default:
			score += 10
		}

		if sig.RecentCriticalAlerts30 > 0 {
			criticalWeight := minInt(60, sig.RecentCriticalAlerts30*24)
			score += criticalWeight
			addReason(fmt.Sprintf("%d recent critical alert(s) in last 30 days", sig.RecentCriticalAlerts30))
		}
		if sig.RecentHighAlerts30 > 0 {
			highWeight := minInt(38, sig.RecentHighAlerts30*14)
			score += highWeight
			addReason(fmt.Sprintf("%d recent high-risk alert(s) in last 30 days", sig.RecentHighAlerts30))
		}
		if sig.RecentEncounterCount == 0 {
			score += 16
			addReason("No recent encounter in the last 30 days")
		}
		if sig.LastEncounterAt != nil {
			daysSince := int(now.Sub(sig.LastEncounterAt.UTC()).Hours() / 24)
			if daysSince >= 45 {
				score += 18
				addReason("Last encounter was over 45 days ago")
			} else if daysSince >= 21 {
				score += 10
			}
		}
		if sig.AgeYears >= 60 {
			score += 12
			addReason("Older adult follow-up requires priority")
		} else if sig.AgeYears > 0 && sig.AgeYears <= 5 {
			score += 14
			addReason("Young child visit needs early review")
		}

		slot := strings.ToLower(strings.TrimSpace(sig.PreferredTimeSlot))
		currentHour := now.Hour()
		switch slot {
		case "morning":
			score += 8
			if currentHour >= 12 {
				score += 12
				addReason("Morning slot is past due")
			}
		case "afternoon":
			if currentHour >= 16 {
				score += 8
				addReason("Afternoon slot is nearing cutoff")
			}
		}

		if score < 0 {
			score = 0
		}
		level := priorityLevelFromScore(score)
		switch level {
		case "critical":
			totals.Critical++
		case "high":
			totals.High++
		case "medium":
			totals.Medium++
		default:
			totals.Low++
		}

		if len(reasons) == 0 {
			reasonLabel := ashaReasonCatalog[sig.ReasonCode]
			if reasonLabel == "" {
				reasonLabel = "General follow-up requirement"
			}
			reasons = append(reasons, reasonLabel)
		}

		ranked = append(ranked, ashaRankedAppointment{
			AppointmentID: sig.AppointmentID,
			PatientID:     sig.PatientID,
			PatientName:   strings.TrimSpace(sig.PatientName),
			PriorityScore: score,
			PriorityLevel: level,
			Reasons:       reasons,
		})
	}

	sort.SliceStable(ranked, func(i, j int) bool {
		if ranked[i].PriorityScore != ranked[j].PriorityScore {
			return ranked[i].PriorityScore > ranked[j].PriorityScore
		}
		return strings.ToLower(ranked[i].PatientName) < strings.ToLower(ranked[j].PatientName)
	})

	return ranked, totals
}

func priorityLevelFromScore(score int) string {
	switch {
	case score >= 115:
		return "critical"
	case score >= 80:
		return "high"
	case score >= 45:
		return "medium"
	default:
		return "low"
	}
}

func buildRuleBasedASHANarrative(ranked []ashaRankedAppointment, totals ashaDaySummaryTotals) ashaDaySummaryNarrative {
	if totals.Appointments == 0 {
		return ashaDaySummaryNarrative{
			SummaryTextShort: "No appointments today.",
			SummaryTextFull:  "No ASHA appointments are scheduled for today.",
			TopFocusPoints:   []string{"No action required right now."},
			RiskNotes:        []string{},
		}
	}

	short := fmt.Sprintf(
		"%d visits today; prioritize %d critical and %d high-risk cases before noon.",
		totals.Appointments,
		totals.Critical,
		totals.High,
	)
	full := fmt.Sprintf(
		"Today has %d scheduled visits: %d critical, %d high, %d medium, and %d low priority. Begin with the highest-ranked patients first and clear the morning-slot backlog early.",
		totals.Appointments,
		totals.Critical,
		totals.High,
		totals.Medium,
		totals.Low,
	)

	topFocus := make([]string, 0, 5)
	if totals.Critical > 0 {
		topFocus = append(topFocus, fmt.Sprintf("Start immediately with %d critical case(s).", totals.Critical))
	}
	if totals.High > 0 {
		topFocus = append(topFocus, fmt.Sprintf("Complete %d high-priority visit(s) before medium-risk work.", totals.High))
	}
	for _, appt := range ranked {
		if len(topFocus) >= 5 {
			break
		}
		if len(appt.Reasons) == 0 {
			continue
		}
		topFocus = append(topFocus, fmt.Sprintf("%s: %s.", nonEmpty(appt.PatientName, "Patient"), appt.Reasons[0]))
	}
	if len(topFocus) == 0 {
		topFocus = append(topFocus, "Process visits in ranked order.")
	}

	riskNotes := make([]string, 0, 4)
	for _, appt := range ranked {
		if appt.PriorityLevel != "critical" && appt.PriorityLevel != "high" {
			continue
		}
		note := fmt.Sprintf("%s marked %s (score %d).", nonEmpty(appt.PatientName, "Patient"), appt.PriorityLevel, appt.PriorityScore)
		riskNotes = append(riskNotes, note)
		if len(riskNotes) >= 4 {
			break
		}
	}

	return ashaDaySummaryNarrative{
		SummaryTextShort: short,
		SummaryTextFull:  full,
		TopFocusPoints:   topFocus,
		RiskNotes:        riskNotes,
	}
}

func (h *Handler) generateASHADaySummaryNarrative(
	ctx context.Context,
	date time.Time,
	tzName string,
	totals ashaDaySummaryTotals,
	ranked []ashaRankedAppointment,
) (ashaDaySummaryNarrative, error) {
	if strings.TrimSpace(h.cfg.BedrockModelID) == "" {
		return ashaDaySummaryNarrative{}, fmt.Errorf("bedrock model id not configured")
	}
	region := defaultString(strings.TrimSpace(h.cfg.BedrockRegion), defaultString(h.cfg.AWSRegion, "ap-south-1"))
	awsCfg, err := awsconfig.LoadDefaultConfig(ctx, awsconfig.WithRegion(region))
	if err != nil {
		return ashaDaySummaryNarrative{}, err
	}
	client := bedrockruntime.NewFromConfig(awsCfg)

	trimmedRanked := ranked
	if len(trimmedRanked) > 12 {
		trimmedRanked = trimmedRanked[:12]
	}
	rankedJSON, _ := json.Marshal(trimmedRanked)
	totalsJSON, _ := json.Marshal(totals)

	prompt := "You are a healthcare operations assistant for ASHA workers. " +
		"Generate concise daily planning text strictly from supplied deterministic ranking. " +
		"Never alter the order, counts, or priority levels. " +
		"Return strict JSON with keys summary_text_short, summary_text_full, top_focus_points, risk_notes. " +
		"summary_text_short must be 1-2 lines. top_focus_points must have 3-5 bullets. risk_notes is optional array. " +
		"Do not include markdown.\n" +
		"Date: " + date.Format("2006-01-02") + "\n" +
		"Timezone: " + tzName + "\n" +
		"Totals JSON: " + string(totalsJSON) + "\n" +
		"Ranked Appointments JSON: " + string(rankedJSON)
	h.logAIDebug("asha_day_summary_prompt", prompt)

	maxTokens := int32(1000)
	temperature := float32(0.0)
	out, err := client.Converse(ctx, &bedrockruntime.ConverseInput{
		ModelId: &h.cfg.BedrockModelID,
		Messages: []bedrocktypes.Message{
			{
				Role: bedrocktypes.ConversationRoleUser,
				Content: []bedrocktypes.ContentBlock{
					&bedrocktypes.ContentBlockMemberText{Value: prompt},
				},
			},
		},
		InferenceConfig: &bedrocktypes.InferenceConfiguration{
			MaxTokens:   &maxTokens,
			Temperature: &temperature,
		},
	})
	if err != nil {
		return ashaDaySummaryNarrative{}, err
	}
	rawText, err := extractTextFromConverseOutput(out)
	if err != nil {
		return ashaDaySummaryNarrative{}, err
	}

	raw := strings.TrimSpace(rawText)
	raw = strings.TrimPrefix(raw, "```json")
	raw = strings.TrimPrefix(raw, "```")
	raw = strings.TrimSuffix(raw, "```")
	raw = strings.TrimSpace(raw)

	var parsed ashaDaySummaryNarrative
	if err := json.Unmarshal([]byte(raw), &parsed); err != nil {
		jsonOnly := extractJSONObject(raw)
		if jsonOnly == "" {
			return ashaDaySummaryNarrative{}, err
		}
		if err2 := json.Unmarshal([]byte(jsonOnly), &parsed); err2 != nil {
			return ashaDaySummaryNarrative{}, err2
		}
	}

	parsed.SummaryTextShort = strings.TrimSpace(parsed.SummaryTextShort)
	parsed.SummaryTextFull = strings.TrimSpace(parsed.SummaryTextFull)
	if parsed.SummaryTextShort == "" || parsed.SummaryTextFull == "" {
		return ashaDaySummaryNarrative{}, fmt.Errorf("empty narrative from AI")
	}
	if len(parsed.TopFocusPoints) > 5 {
		parsed.TopFocusPoints = parsed.TopFocusPoints[:5]
	}
	if len(parsed.TopFocusPoints) < 3 {
		return ashaDaySummaryNarrative{}, fmt.Errorf("insufficient focus points from AI")
	}
	return parsed, nil
}

func minInt(a, b int) int {
	return int(math.Min(float64(a), float64(b)))
}

func nonEmpty(v, fallback string) string {
	if strings.TrimSpace(v) == "" {
		return fallback
	}
	return strings.TrimSpace(v)
}
