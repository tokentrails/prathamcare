package api

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
	"github.com/prathamcare/backend/internal/models"
)

var ashaReasonCatalog = map[string]string{
	"home_visit_follow_up":      "Home visit follow-up",
	"maternal_newborn_follow_up": "Maternal/newborn follow-up",
	"immunization_mobilization":  "Immunization mobilization",
	"family_planning_counseling": "Family planning counseling",
	"referral_support":           "Referral support",
	"community_follow_up":        "Community-level follow-up",
	"general_health_check":       "General health check",
}

var allowedASHAStatusTransitions = map[string]map[string]bool{
	"requested": {
		"assigned":   true,
		"accepted":   true,
		"cancelled":  true,
		"unassigned": true,
	},
	"assigned": {
		"accepted":   true,
		"in_progress": true,
		"cancelled":  true,
		"unassigned": true,
	},
	"accepted": {
		"in_progress": true,
		"cancelled":  true,
	},
	"in_progress": {
		"completed": true,
		"cancelled": true,
	},
	"unassigned": {
		"assigned":  true,
		"cancelled": true,
	},
	"completed": {},
	"cancelled": {},
}

type publicASHAAppointmentRequest struct {
	RequestorName     string   `json:"requestor_name"`
	RequestorPhone    string   `json:"requestor_phone"`
	RequestorEmail    string   `json:"requestor_email"`
	ABHANumber        string   `json:"abha_number"`
	ReasonCode        string   `json:"reason_code"`
	ReasonText        string   `json:"reason_text"`
	PreferredDate     string   `json:"preferred_date"`
	PreferredTimeSlot string   `json:"preferred_time_slot"`
	VisitType         string   `json:"visit_type"`
	AddressLine1      string   `json:"address_line1"`
	AddressLine2      string   `json:"address_line2"`
	VillageOrWard     string   `json:"village_or_ward"`
	GramPanchayat     string   `json:"gram_panchayat"`
	BlockOrTaluk      string   `json:"block_or_taluk"`
	District          string   `json:"district"`
	State             string   `json:"state"`
	Pincode           string   `json:"pincode"`
	Latitude          *float64 `json:"latitude"`
	Longitude         *float64 `json:"longitude"`
	SourceChannel     string   `json:"source_channel"`
}

type ashaAppointmentStatusUpdateRequest struct {
	Status string `json:"status"`
}

type ashaAppointmentCompleteRequest struct {
	EncounterID string `json:"encounter_id"`
}

func (h *Handler) handlePublicASHAAppointmentRequest(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "service unavailable")
	}

	var in publicASHAAppointmentRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	if errCode, errMsg := validatePublicASHAAppointmentRequest(&in); errCode != "" {
		return h.error(http.StatusBadRequest, errCode, errMsg)
	}

	ipAddress := strings.TrimSpace(req.RequestContext.HTTP.SourceIP)
	if ipAddress == "" {
		ipAddress = "unknown"
	}

	rateCtx, cancelRate := context.WithTimeout(ctx, 2*time.Second)
	recentCount, rateErr := h.deps.Aurora.CountRecentPublicAppointmentRequests(rateCtx, in.RequestorPhone, ipAddress, 15*time.Minute)
	cancelRate()
	if rateErr == nil && recentCount >= 5 {
		return h.error(http.StatusTooManyRequests, "RATE_LIMIT_EXCEEDED", "request limit reached. Please try again later")
	}

	dupCtx, cancelDup := context.WithTimeout(ctx, 2*time.Second)
	duplicate, dupErr := h.deps.Aurora.HasRecentDuplicatePublicAppointment(dupCtx, in.RequestorPhone, in.ReasonCode, in.Pincode, 10*time.Minute)
	cancelDup()
	if dupErr == nil && duplicate {
		return h.error(http.StatusTooManyRequests, "RATE_LIMIT_EXCEEDED", "a similar request was recently received")
	}

	patient, pErr := h.ensurePublicRequestPatient(ctx, in)
	if pErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "unable to process appointment request")
	}

	match := models.ASHAMatchResult{}
	matchCtx, cancelMatch := context.WithTimeout(ctx, 4*time.Second)
	match, mErr := h.deps.Aurora.MatchASHAByLocation(
		matchCtx,
		in.VillageOrWard,
		in.BlockOrTaluk,
		in.District,
		in.State,
		in.Pincode,
		in.Latitude,
		in.Longitude,
	)
	cancelMatch()
	if mErr != nil && !errors.Is(mErr, pgx.ErrNoRows) {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "unable to process appointment request")
	}

	status := "unassigned"
	if match.ASHAUserID != "" {
		status = "assigned"
	}
	if strings.TrimSpace(in.VisitType) == "" {
		in.VisitType = "home_visit"
	}
	if strings.TrimSpace(in.SourceChannel) == "" {
		in.SourceChannel = "public_web"
	}

	notes := map[string]any{
		"request_ip":  ipAddress,
		"user_agent":  strings.TrimSpace(headerValue(req.Headers, "User-Agent")),
		"reason_label": ashaReasonCatalog[in.ReasonCode],
	}
	apptCreateCtx, cancelCreate := context.WithTimeout(ctx, 4*time.Second)
	created, cErr := h.deps.Aurora.CreateASHAAppointment(apptCreateCtx, models.ASHAAppointment{
		PatientID:         patient.PatientID,
		ASHAUserID:        match.ASHAUserID,
		Status:            status,
		ReasonCode:        in.ReasonCode,
		ReasonText:        in.ReasonText,
		PreferredDate:     in.PreferredDate,
		PreferredTimeSlot: in.PreferredTimeSlot,
		VisitType:         in.VisitType,
		SourceChannel:     in.SourceChannel,
		RequestorName:     in.RequestorName,
		RequestorPhone:    in.RequestorPhone,
		RequestorEmail:    in.RequestorEmail,
		AddressLine1:      in.AddressLine1,
		AddressLine2:      in.AddressLine2,
		VillageOrWard:     in.VillageOrWard,
		GramPanchayat:     in.GramPanchayat,
		BlockOrTaluk:      in.BlockOrTaluk,
		District:          in.District,
		State:             in.State,
		Pincode:           in.Pincode,
		Latitude:          valueOrZero(in.Latitude),
		Longitude:         valueOrZero(in.Longitude),
		AssignedMethod:    match.AssignedMethod,
		AssignmentScore:   match.AssignmentScore,
		Notes:             asJSONString(notes),
	})
	cancelCreate()
	if cErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "unable to process appointment request")
	}

	evtCtx, cancelEvt := context.WithTimeout(ctx, 2*time.Second)
	_ = h.deps.Aurora.LogASHAAppointmentEvent(evtCtx, models.ASHAAppointmentEvent{
		AppointmentID: created.AppointmentID,
		EventType:     "requested",
		EventPayload:  fmt.Sprintf(`{"source_channel":"%s"}`, in.SourceChannel),
		CreatedBy:     "public",
	})
	if status == "assigned" {
		_ = h.deps.Aurora.LogASHAAppointmentEvent(evtCtx, models.ASHAAppointmentEvent{
			AppointmentID: created.AppointmentID,
			EventType:     "assigned",
			EventPayload:  fmt.Sprintf(`{"asha_user_id":"%s","assigned_method":"%s","assignment_score":%.2f}`, created.ASHAUserID, created.AssignedMethod, created.AssignmentScore),
			CreatedBy:     "system",
		})
	} else {
		_ = h.deps.Aurora.LogASHAAppointmentEvent(evtCtx, models.ASHAAppointmentEvent{
			AppointmentID: created.AppointmentID,
			EventType:     "unassigned",
			EventPayload:  `{"reason":"no_matching_asha"}`,
			CreatedBy:     "system",
		})
	}
	cancelEvt()

	message := "Appointment request received. An ASHA worker will be assigned shortly."
	if status == "assigned" {
		message = "Appointment request received and assigned to an ASHA worker."
	}

	return h.json(http.StatusCreated, map[string]any{
		"appointment_id":     created.AppointmentID,
		"status":             created.Status,
		"assigned_asha_id":   created.ASHAUserID,
		"patient_id":         created.PatientID,
		"message":            message,
		"reason_code":        created.ReasonCode,
		"reason_label":       ashaReasonCatalog[created.ReasonCode],
		"preferred_date":     created.PreferredDate,
		"preferred_time_slot": created.PreferredTimeSlot,
	})
}

func (h *Handler) ensurePublicRequestPatient(ctx context.Context, in publicASHAAppointmentRequest) (models.Patient, error) {
	findCtx, cancelFind := context.WithTimeout(ctx, 3*time.Second)
	patient, err := h.deps.Aurora.FindPatientForPublicRequest(findCtx, in.RequestorPhone, in.RequestorName, in.Pincode, in.ABHANumber)
	cancelFind()
	if err == nil {
		return patient, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return models.Patient{}, err
	}

	firstName, lastName := splitName(in.RequestorName)
	createCtx, cancelCreate := context.WithTimeout(ctx, 4*time.Second)
	created, createErr := h.deps.Aurora.CreatePatient(createCtx, models.Patient{
		FHIRPatientID:     "local-public-" + newID(),
		ABHANumber:        in.ABHANumber,
		FirstName:         firstName,
		LastName:          lastName,
		FullName:          strings.TrimSpace(in.RequestorName),
		Gender:            "unknown",
		Phone:             in.RequestorPhone,
		PhoneNumber:       in.RequestorPhone,
		PhoneE164:         in.RequestorPhone,
		Email:             in.RequestorEmail,
		AddressLine1:      in.AddressLine1,
		AddressLine2:      in.AddressLine2,
		VillageOrWard:     in.VillageOrWard,
		GramPanchayat:     in.GramPanchayat,
		BlockOrTaluk:      in.BlockOrTaluk,
		District:          in.District,
		State:             in.State,
		Pincode:           in.Pincode,
		ConsentFlags:      "{}",
		Status:            "active",
		PreferredLanguage: "hi",
		SourceSystem:      "public_intake",
		ReadOnly:          false,
		LastSyncedAt:      time.Now().UTC(),
	})
	cancelCreate()
	if createErr != nil {
		return models.Patient{}, createErr
	}
	return created, nil
}

func (h *Handler) handleASHAAppointmentsList(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 2*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	params := req.QueryStringParameters
	status := strings.ToLower(strings.TrimSpace(params["status"]))
	if status != "" && !isValidASHAAppointmentStatus(status) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid status filter")
	}

	readCtx, cancelRead := context.WithTimeout(ctx, 4*time.Second)
	items, lErr := h.deps.Aurora.ListASHAAppointments(readCtx, models.ASHAAppointmentListFilter{
		ASHAUserID: ownerID,
		FromDate:   strings.TrimSpace(params["from"]),
		ToDate:     strings.TrimSpace(params["to"]),
		Status:     status,
		Limit:      parseLimit(params, 20, 100),
	})
	cancelRead()
	if lErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to list appointments")
	}

	respItems := make([]map[string]any, 0, len(items))
	for _, it := range items {
		respItems = append(respItems, ashaAppointmentResponse(it))
	}
	return h.json(http.StatusOK, map[string]any{
		"items": respItems,
		"count": len(respItems),
	})
}

func (h *Handler) handleASHAAppointmentGet(ctx context.Context, req events.APIGatewayV2HTTPRequest, appointmentID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}
	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 2*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	readCtx, cancelRead := context.WithTimeout(ctx, 4*time.Second)
	item, gErr := h.deps.Aurora.GetASHAAppointmentByIDForASHA(readCtx, appointmentID, ownerID)
	cancelRead()
	if gErr != nil {
		if errors.Is(gErr, pgx.ErrNoRows) {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "appointment not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load appointment")
	}
	return h.json(http.StatusOK, ashaAppointmentResponse(item))
}

func (h *Handler) handleASHAAppointmentStatusPatch(ctx context.Context, req events.APIGatewayV2HTTPRequest, appointmentID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 2*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	var in ashaAppointmentStatusUpdateRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	targetStatus := strings.ToLower(strings.TrimSpace(in.Status))
	if !isValidASHAAppointmentStatus(targetStatus) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid status")
	}

	readCtx, cancelRead := context.WithTimeout(ctx, 4*time.Second)
	current, gErr := h.deps.Aurora.GetASHAAppointmentByIDForASHA(readCtx, appointmentID, ownerID)
	cancelRead()
	if gErr != nil {
		if errors.Is(gErr, pgx.ErrNoRows) {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "appointment not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load appointment")
	}
	if !isAllowedStatusTransition(current.Status, targetStatus) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid status transition")
	}

	writeCtx, cancelWrite := context.WithTimeout(ctx, 4*time.Second)
	uErr := h.deps.Aurora.UpdateASHAAppointmentStatus(writeCtx, appointmentID, targetStatus, ownerID)
	cancelWrite()
	if uErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to update appointment")
	}

	refetchCtx, cancelRefetch := context.WithTimeout(ctx, 4*time.Second)
	updated, rErr := h.deps.Aurora.GetASHAAppointmentByIDForASHA(refetchCtx, appointmentID, ownerID)
	cancelRefetch()
	if rErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load appointment")
	}
	return h.json(http.StatusOK, ashaAppointmentResponse(updated))
}

func (h *Handler) handleASHAAppointmentStartEncounter(ctx context.Context, req events.APIGatewayV2HTTPRequest, appointmentID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 2*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	readCtx, cancelRead := context.WithTimeout(ctx, 4*time.Second)
	appt, gErr := h.deps.Aurora.GetASHAAppointmentByIDForASHA(readCtx, appointmentID, ownerID)
	cancelRead()
	if gErr != nil {
		if errors.Is(gErr, pgx.ErrNoRows) {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "appointment not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load appointment")
	}

	if appt.Status == "requested" || appt.Status == "assigned" || appt.Status == "accepted" {
		writeCtx, cancelWrite := context.WithTimeout(ctx, 3*time.Second)
		_ = h.deps.Aurora.UpdateASHAAppointmentStatus(writeCtx, appointmentID, "in_progress", ownerID)
		cancelWrite()
		appt.Status = "in_progress"
	}

	viewerRef, viewerUUID := h.resolveViewer(ctx, claims.Subject)
	patientCtx, cancelPatient := context.WithTimeout(ctx, 3*time.Second)
	patient, pErr := h.deps.Aurora.GetPatientByIDForUser(patientCtx, viewerRef, viewerUUID, appt.PatientID)
	cancelPatient()
	if pErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load patient context")
	}

	return h.json(http.StatusOK, map[string]any{
		"appointment": ashaAppointmentResponse(appt),
		"patient":     patientDetailResponse(patient),
		"launch": map[string]any{
			"patient_id":     appt.PatientID,
			"appointment_id": appt.AppointmentID,
			"visit_type":     appt.VisitType,
		},
	})
}

func (h *Handler) handleASHAAppointmentComplete(ctx context.Context, req events.APIGatewayV2HTTPRequest, appointmentID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	ownerID := claims.Subject
	resolveCtx, cancelResolve := context.WithTimeout(ctx, 2*time.Second)
	if resolved, resolveErr := h.resolveASHAUserID(resolveCtx, claims.Subject); resolveErr == nil {
		ownerID = resolved
	}
	cancelResolve()

	var in ashaAppointmentCompleteRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	if strings.TrimSpace(in.EncounterID) == "" {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "encounter_id is required")
	}

	readCtx, cancelRead := context.WithTimeout(ctx, 4*time.Second)
	_, gErr := h.deps.Aurora.GetASHAAppointmentByIDForASHA(readCtx, appointmentID, ownerID)
	cancelRead()
	if gErr != nil {
		if errors.Is(gErr, pgx.ErrNoRows) {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "appointment not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load appointment")
	}

	writeCtx, cancelWrite := context.WithTimeout(ctx, 4*time.Second)
	cErr := h.deps.Aurora.CompleteASHAAppointment(writeCtx, appointmentID, in.EncounterID, ownerID)
	cancelWrite()
	if cErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to complete appointment")
	}

	refetchCtx, cancelRefetch := context.WithTimeout(ctx, 4*time.Second)
	updated, rErr := h.deps.Aurora.GetASHAAppointmentByIDForASHA(refetchCtx, appointmentID, ownerID)
	cancelRefetch()
	if rErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load appointment")
	}

	return h.json(http.StatusOK, map[string]any{
		"appointment": ashaAppointmentResponse(updated),
		"message":     "appointment marked completed",
	})
}

func validatePublicASHAAppointmentRequest(in *publicASHAAppointmentRequest) (string, string) {
	in.RequestorName = strings.TrimSpace(in.RequestorName)
	in.RequestorPhone = strings.TrimSpace(in.RequestorPhone)
	in.RequestorEmail = strings.TrimSpace(in.RequestorEmail)
	in.ABHANumber = normalizeABHA(in.ABHANumber)
	in.ReasonCode = strings.ToLower(strings.TrimSpace(in.ReasonCode))
	in.ReasonText = strings.TrimSpace(in.ReasonText)
	in.PreferredDate = strings.TrimSpace(in.PreferredDate)
	in.PreferredTimeSlot = strings.ToLower(strings.TrimSpace(in.PreferredTimeSlot))
	in.VisitType = strings.ToLower(strings.TrimSpace(in.VisitType))
	in.AddressLine1 = strings.TrimSpace(in.AddressLine1)
	in.AddressLine2 = strings.TrimSpace(in.AddressLine2)
	in.VillageOrWard = strings.TrimSpace(in.VillageOrWard)
	in.GramPanchayat = strings.TrimSpace(in.GramPanchayat)
	in.BlockOrTaluk = strings.TrimSpace(in.BlockOrTaluk)
	in.District = strings.TrimSpace(in.District)
	in.State = strings.TrimSpace(in.State)
	in.Pincode = strings.TrimSpace(in.Pincode)
	in.SourceChannel = strings.ToLower(strings.TrimSpace(in.SourceChannel))

	if in.RequestorName == "" {
		return "MISSING_REQUIRED_FIELD", "requestor_name is required"
	}
	if in.RequestorPhone == "" {
		return "MISSING_REQUIRED_FIELD", "requestor_phone is required"
	}
	normalizedPhone, pErr := normalizeIndianPhone(in.RequestorPhone)
	if pErr != nil {
		return "VALIDATION_ERROR", pErr.Error()
	}
	in.RequestorPhone = normalizedPhone

	if in.AddressLine1 == "" {
		return "MISSING_REQUIRED_FIELD", "address_line1 is required"
	}
	if in.District == "" {
		return "MISSING_REQUIRED_FIELD", "district is required"
	}
	if in.State == "" {
		return "MISSING_REQUIRED_FIELD", "state is required"
	}
	if !regexp.MustCompile(`^[0-9]{6}$`).MatchString(in.Pincode) {
		return "VALIDATION_ERROR", "pincode must be 6 digits"
	}
	if in.ReasonCode == "" {
		return "MISSING_REQUIRED_FIELD", "reason_code is required"
	}
	if _, ok := ashaReasonCatalog[in.ReasonCode]; !ok {
		return "VALIDATION_ERROR", "invalid reason_code"
	}
	if in.ABHANumber != "" && !isValidABHA(in.ABHANumber) {
		return "VALIDATION_ERROR", "abha_number must be 14 digits"
	}
	if in.PreferredDate != "" {
		dateOnly, err := parseDateOnly(in.PreferredDate)
		if err != nil {
			return "VALIDATION_ERROR", "preferred_date must be YYYY-MM-DD"
		}
		in.PreferredDate = dateOnly
	}
	if in.PreferredTimeSlot != "" && in.PreferredTimeSlot != "morning" && in.PreferredTimeSlot != "afternoon" && in.PreferredTimeSlot != "evening" {
		return "VALIDATION_ERROR", "preferred_time_slot must be morning, afternoon, or evening"
	}
	if strings.TrimSpace(in.VisitType) == "" {
		in.VisitType = "home_visit"
	}
	return "", ""
}

func isAllowedStatusTransition(current, next string) bool {
	current = strings.ToLower(strings.TrimSpace(current))
	next = strings.ToLower(strings.TrimSpace(next))
	if current == next {
		return true
	}
	nextStates, ok := allowedASHAStatusTransitions[current]
	if !ok {
		return false
	}
	return nextStates[next]
}

func isValidASHAAppointmentStatus(status string) bool {
	switch strings.ToLower(strings.TrimSpace(status)) {
	case "requested", "assigned", "accepted", "in_progress", "completed", "cancelled", "unassigned":
		return true
	default:
		return false
	}
}

func ashaAppointmentResponse(a models.ASHAAppointment) map[string]any {
	return map[string]any{
		"appointment_id":       a.AppointmentID,
		"patient_id":           a.PatientID,
		"asha_user_id":         a.ASHAUserID,
		"status":               a.Status,
		"reason_code":          a.ReasonCode,
		"reason_label":         ashaReasonCatalog[a.ReasonCode],
		"reason_text":          a.ReasonText,
		"preferred_date":       a.PreferredDate,
		"preferred_time_slot":  a.PreferredTimeSlot,
		"visit_type":           a.VisitType,
		"source_channel":       a.SourceChannel,
		"requestor_name":       a.RequestorName,
		"requestor_phone_masked": maskPhone(a.RequestorPhone),
		"requestor_email_masked": maskEmail(a.RequestorEmail),
		"address_line1":        a.AddressLine1,
		"address_line2":        a.AddressLine2,
		"village_or_ward":      a.VillageOrWard,
		"gram_panchayat":       a.GramPanchayat,
		"block_or_taluk":       a.BlockOrTaluk,
		"district":             a.District,
		"state":                a.State,
		"pincode":              a.Pincode,
		"assigned_method":      a.AssignedMethod,
		"assignment_score":     a.AssignmentScore,
		"encounter_id":         a.EncounterID,
		"created_at":           a.CreatedAt.UTC().Format(time.RFC3339),
		"updated_at":           a.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

func splitName(fullName string) (string, string) {
	parts := strings.Fields(strings.TrimSpace(fullName))
	if len(parts) == 0 {
		return "Unknown", ""
	}
	if len(parts) == 1 {
		return parts[0], ""
	}
	return parts[0], strings.Join(parts[1:], " ")
}

func valueOrZero(v *float64) float64 {
	if v == nil {
		return 0
	}
	return *v
}
