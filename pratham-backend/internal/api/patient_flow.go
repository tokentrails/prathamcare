package api

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"regexp"
	"strings"
	"time"

	"github.com/aws/aws-lambda-go/events"
	"github.com/jackc/pgx/v5"
	"github.com/prathamcare/backend/internal/models"
)

type patientUpsertRequest struct {
	ABHANumber     string         `json:"abha_number"`
	ABHAAddress    string         `json:"abha_address"`
	FirstName      string         `json:"first_name"`
	MiddleName     string         `json:"middle_name"`
	LastName       string         `json:"last_name"`
	Gender         string         `json:"gender"`
	DateOfBirth    string         `json:"date_of_birth"`
	AgeYears       int            `json:"age_years"`
	PhoneNumber    string         `json:"phone_number"`
	Email          string         `json:"email"`
	AddressLine1   string         `json:"address_line1"`
	AddressLine2   string         `json:"address_line2"`
	VillageOrWard  string         `json:"village_or_ward"`
	GramPanchayat  string         `json:"gram_panchayat"`
	BlockOrTaluk   string         `json:"block_or_taluk"`
	District       string         `json:"district"`
	State          string         `json:"state"`
	Pincode        string         `json:"pincode"`
	Landmark       string         `json:"landmark"`
	ConsentFlags   map[string]any `json:"consent_flags"`
	PreferredLang  string         `json:"preferred_language"`
	Status         string         `json:"status"`
}

func (h *Handler) handlePatientCreate(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	var in patientUpsertRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	patient, code, message := preparePatientModel(in)
	if code != "" {
		return h.error(http.StatusBadRequest, code, message)
	}

	viewerRef := h.resolveViewerRef(ctx, claims.Subject)
	patient.CreatedBy = viewerRef
	patient.UpdatedBy = viewerRef
	patient.SourceSystem = "app"
	patient.ReadOnly = false
	patient.LastSyncedAt = time.Now().UTC()
	patient.FHIRPatientID = "local-" + newID()
	if patient.Status == "" {
		patient.Status = "active"
	}

	writeCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	created, cErr := h.deps.Aurora.CreatePatient(writeCtx, patient)
	if cErr != nil {
		if strings.Contains(strings.ToLower(cErr.Error()), "idx_patients_abha") || strings.Contains(strings.ToLower(cErr.Error()), "duplicate key") {
			return h.error(http.StatusConflict, "DUPLICATE_ABHA", "ABHA number already exists")
		}
		log.Printf("patient_create_failed sub=%s phone=%s abha=%s error=%v", claims.Subject, maskPhone(patient.PhoneE164), maskABHA(patient.ABHANumber), cErr)
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to create patient")
	}

	log.Printf("patient_create_done sub=%s patient_id=%s phone=%s abha=%s", claims.Subject, created.PatientID, maskPhone(created.PhoneE164), maskABHA(created.ABHANumber))
	return h.json(http.StatusCreated, patientDetailResponse(created))
}

func (h *Handler) handlePatientSearch(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	params := req.QueryStringParameters
	query := strings.TrimSpace(params["q"])
	phone := strings.TrimSpace(params["phone"])
	abha := normalizeABHA(strings.TrimSpace(params["abha"]))
	limit := parseLimit(params, 10, 50)
	if query == "" && phone == "" && abha == "" {
		return h.error(http.StatusBadRequest, "MISSING_REQUIRED_FIELD", "at least one of q, phone, or abha is required")
	}

	normalizedPhone := ""
	if phone != "" {
		var pErr error
		normalizedPhone, pErr = normalizeIndianPhone(phone)
		if pErr != nil {
			return h.error(http.StatusBadRequest, "INVALID_PHONE", pErr.Error())
		}
	}
	if strings.TrimSpace(abha) != "" && !isValidABHA(abha) {
		return h.error(http.StatusBadRequest, "INVALID_ABHA_FORMAT", "abha_number must be 14 digits")
	}

	viewerRef, viewerUUID := h.resolveViewer(ctx, claims.Subject)
	patientRef := ""
	if looksLikeUUID(query) || strings.HasPrefix(strings.ToLower(query), "local-") {
		patientRef = query
	}
	readCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	patients, sErr := h.deps.Aurora.SearchPatients(readCtx, viewerRef, viewerUUID, models.PatientSearchFilter{
		Query:      query,
		PhoneE164:  normalizedPhone,
		ABHANumber: abha,
		PatientRef: patientRef,
		Limit:      limit,
	})
	if sErr != nil {
		log.Printf("patient_search_failed sub=%s q=%q phone=%s abha=%s error=%v", claims.Subject, query, maskPhone(normalizedPhone), maskABHA(abha), sErr)
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to search patients")
	}

	items := make([]map[string]any, 0, len(patients))
	for _, p := range patients {
		items = append(items, patientSearchCard(p))
	}
	return h.json(http.StatusOK, map[string]any{
		"results": items,
		"count":   len(items),
	})
}

func (h *Handler) handlePatientGet(ctx context.Context, req events.APIGatewayV2HTTPRequest, patientID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}
	if !looksLikeUUID(patientID) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid patient_id")
	}

	viewerRef, viewerUUID := h.resolveViewer(ctx, claims.Subject)
	readCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	patient, gErr := h.deps.Aurora.GetPatientByIDForUser(readCtx, viewerRef, viewerUUID, patientID)
	if gErr != nil {
		if gErr == pgx.ErrNoRows || strings.Contains(strings.ToLower(gErr.Error()), "no rows") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "patient not found")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to load patient")
	}

	return h.json(http.StatusOK, patientDetailResponse(patient))
}

func (h *Handler) handlePatientUpdate(ctx context.Context, req events.APIGatewayV2HTTPRequest, patientID string) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}
	if !looksLikeUUID(patientID) {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid patient_id")
	}

	var in patientUpsertRequest
	if err := json.Unmarshal([]byte(req.Body), &in); err != nil {
		return h.error(http.StatusBadRequest, "VALIDATION_ERROR", "invalid request body")
	}
	patient, code, message := preparePatientModel(in)
	if code != "" {
		return h.error(http.StatusBadRequest, code, message)
	}
	patient.PatientID = patientID
	patient.UpdatedBy = h.resolveViewerRef(ctx, claims.Subject)

	viewerRef, viewerUUID := h.resolveViewer(ctx, claims.Subject)
	writeCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	updated, uErr := h.deps.Aurora.UpdatePatient(writeCtx, viewerRef, viewerUUID, patient)
	if uErr != nil {
		if uErr == pgx.ErrNoRows || strings.Contains(strings.ToLower(uErr.Error()), "no rows") {
			return h.error(http.StatusNotFound, "RESOURCE_NOT_FOUND", "patient not found")
		}
		if strings.Contains(strings.ToLower(uErr.Error()), "idx_patients_abha") || strings.Contains(strings.ToLower(uErr.Error()), "duplicate key") {
			return h.error(http.StatusConflict, "DUPLICATE_ABHA", "ABHA number already exists")
		}
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to update patient")
	}

	return h.json(http.StatusOK, patientDetailResponse(updated))
}

func (h *Handler) handlePatientRecent(ctx context.Context, req events.APIGatewayV2HTTPRequest) (events.APIGatewayV2HTTPResponse, error) {
	claims, err := h.authorize(req, "asha_worker")
	if err != nil {
		return h.error(http.StatusUnauthorized, "AUTHENTICATION_FAILED", err.Error())
	}
	if h.deps == nil || h.deps.Aurora == nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "aurora repository is not configured")
	}

	limit := parseLimit(req.QueryStringParameters, 10, 50)
	viewerRef, viewerUUID := h.resolveViewer(ctx, claims.Subject)
	readCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
	defer cancel()
	patients, lErr := h.deps.Aurora.ListRecentPatientsByUser(readCtx, viewerRef, viewerUUID, limit)
	if lErr != nil {
		return h.error(http.StatusServiceUnavailable, "SERVICE_UNAVAILABLE", "failed to fetch recent patients")
	}

	items := make([]map[string]any, 0, len(patients))
	for _, p := range patients {
		items = append(items, patientSearchCard(p))
	}
	return h.json(http.StatusOK, map[string]any{
		"results": items,
		"count":   len(items),
	})
}

func preparePatientModel(in patientUpsertRequest) (models.Patient, string, string) {
	in.FirstName = strings.TrimSpace(in.FirstName)
	in.MiddleName = strings.TrimSpace(in.MiddleName)
	in.LastName = strings.TrimSpace(in.LastName)
	in.Gender = strings.ToLower(strings.TrimSpace(in.Gender))
	in.DateOfBirth = strings.TrimSpace(in.DateOfBirth)
	in.PhoneNumber = strings.TrimSpace(in.PhoneNumber)
	in.Email = strings.TrimSpace(in.Email)
	in.AddressLine1 = strings.TrimSpace(in.AddressLine1)
	in.AddressLine2 = strings.TrimSpace(in.AddressLine2)
	in.VillageOrWard = strings.TrimSpace(in.VillageOrWard)
	in.GramPanchayat = strings.TrimSpace(in.GramPanchayat)
	in.BlockOrTaluk = strings.TrimSpace(in.BlockOrTaluk)
	in.District = strings.TrimSpace(in.District)
	in.State = strings.TrimSpace(in.State)
	in.Pincode = strings.TrimSpace(in.Pincode)
	in.Landmark = strings.TrimSpace(in.Landmark)
	in.ABHANumber = normalizeABHA(in.ABHANumber)
	in.ABHAAddress = strings.TrimSpace(in.ABHAAddress)
	in.Status = strings.ToLower(strings.TrimSpace(in.Status))
	in.PreferredLang = strings.TrimSpace(in.PreferredLang)

	if in.FirstName == "" {
		return models.Patient{}, "MISSING_REQUIRED_FIELD", "first_name is required"
	}
	if in.Gender == "" {
		return models.Patient{}, "MISSING_REQUIRED_FIELD", "gender is required"
	}
	if !isAllowedGender(in.Gender) {
		return models.Patient{}, "VALIDATION_ERROR", "gender must be one of male/female/other/unknown"
	}
	if in.AddressLine1 == "" {
		return models.Patient{}, "MISSING_REQUIRED_FIELD", "address_line1 is required"
	}
	if in.District == "" {
		return models.Patient{}, "MISSING_REQUIRED_FIELD", "district is required"
	}
	if in.State == "" {
		return models.Patient{}, "MISSING_REQUIRED_FIELD", "state is required"
	}
	if !regexp.MustCompile(`^\d{6}$`).MatchString(in.Pincode) {
		return models.Patient{}, "INVALID_PINCODE", "pincode must be 6 digits"
	}
	normalizedPhone, pErr := normalizeIndianPhone(in.PhoneNumber)
	if pErr != nil {
		return models.Patient{}, "INVALID_PHONE", pErr.Error()
	}
	if in.ABHANumber != "" && !isValidABHA(in.ABHANumber) {
		return models.Patient{}, "INVALID_ABHA_FORMAT", "abha_number must be 14 digits"
	}

	dob := ""
	if in.DateOfBirth != "" {
		parsedDOB, dErr := parseDateOnly(in.DateOfBirth)
		if dErr != nil {
			return models.Patient{}, "VALIDATION_ERROR", "date_of_birth must be YYYY-MM-DD"
		}
		dob = parsedDOB
	}
	if dob == "" && in.AgeYears <= 0 {
		return models.Patient{}, "MISSING_REQUIRED_FIELD", "date_of_birth or age_years is required"
	}
	if in.AgeYears < 0 || in.AgeYears > 130 {
		return models.Patient{}, "VALIDATION_ERROR", "age_years must be between 0 and 130"
	}
	if in.Status == "" {
		in.Status = "active"
	}
	if in.Status != "active" && in.Status != "inactive" {
		return models.Patient{}, "VALIDATION_ERROR", "status must be active or inactive"
	}
	if in.PreferredLang == "" {
		in.PreferredLang = "hi"
	}

	consentJSON := "{}"
	if in.ConsentFlags != nil {
		if b, err := json.Marshal(in.ConsentFlags); err == nil {
			consentJSON = string(b)
		}
	}

	lastName := in.LastName
	fullName := strings.TrimSpace(strings.Join([]string{in.FirstName, in.MiddleName, lastName}, " "))
	return models.Patient{
		ABHAID:            in.ABHANumber,
		ABHANumber:        in.ABHANumber,
		ABHAAddress:       in.ABHAAddress,
		FirstName:         in.FirstName,
		MiddleName:        in.MiddleName,
		LastName:          in.LastName,
		FullName:          fullName,
		Gender:            in.Gender,
		DateOfBirth:       dob,
		AgeYears:          in.AgeYears,
		Phone:             normalizedPhone,
		PhoneNumber:       normalizedPhone,
		PhoneE164:         normalizedPhone,
		Email:             in.Email,
		AddressLine1:      in.AddressLine1,
		AddressLine2:      in.AddressLine2,
		VillageOrWard:     in.VillageOrWard,
		GramPanchayat:     in.GramPanchayat,
		BlockOrTaluk:      in.BlockOrTaluk,
		District:          in.District,
		State:             in.State,
		Pincode:           in.Pincode,
		Landmark:          in.Landmark,
		ConsentFlags:      consentJSON,
		Status:            in.Status,
		PreferredLanguage: in.PreferredLang,
	}, "", ""
}

func patientDetailResponse(p models.Patient) map[string]any {
	return map[string]any{
		"patient_id":        p.PatientID,
		"fhir_patient_id":   p.FHIRPatientID,
		"abha_number":       p.ABHANumber,
		"abha_address":      p.ABHAAddress,
		"first_name":        p.FirstName,
		"middle_name":       p.MiddleName,
		"last_name":         p.LastName,
		"full_name":         p.FullName,
		"gender":            p.Gender,
		"date_of_birth":     p.DateOfBirth,
		"age_years":         p.AgeYears,
		"phone_number":      p.PhoneE164,
		"email":             p.Email,
		"address_line1":     p.AddressLine1,
		"address_line2":     p.AddressLine2,
		"village_or_ward":   p.VillageOrWard,
		"gram_panchayat":    p.GramPanchayat,
		"block_or_taluk":    p.BlockOrTaluk,
		"district":          p.District,
		"state":             p.State,
		"pincode":           p.Pincode,
		"landmark":          p.Landmark,
		"consent_flags":     parseJSONMap(p.ConsentFlags),
		"created_by":        p.CreatedBy,
		"updated_by":        p.UpdatedBy,
		"status":            p.Status,
		"preferred_language": p.PreferredLanguage,
		"created_at":        p.CreatedAt.UTC().Format(time.RFC3339),
		"updated_at":        p.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

func patientSearchCard(p models.Patient) map[string]any {
	age := p.AgeYears
	if age <= 0 {
		age = parseAgeFromDOB(p.DateOfBirth)
	}
	return map[string]any{
		"patient_id":      p.PatientID,
		"name":            strings.TrimSpace(p.FullName),
		"gender":          p.Gender,
		"date_of_birth":   p.DateOfBirth,
		"age_years":       age,
		"phone_masked":    maskPhone(p.PhoneE164),
		"village_or_ward": p.VillageOrWard,
		"district":        p.District,
		"abha_masked":     maskABHA(p.ABHANumber),
		"status":          p.Status,
	}
}

func parseJSONMap(raw string) map[string]any {
	out := map[string]any{}
	if strings.TrimSpace(raw) == "" {
		return out
	}
	_ = json.Unmarshal([]byte(raw), &out)
	return out
}

func parseDateOnly(v string) (string, error) {
	v = strings.TrimSpace(v)
	if v == "" {
		return "", nil
	}
	if parsed, err := time.Parse("2006-01-02", v); err == nil {
		return parsed.Format("2006-01-02"), nil
	}
	if parsed, err := time.Parse(time.RFC3339, v); err == nil {
		return parsed.UTC().Format("2006-01-02"), nil
	}
	return "", fmt.Errorf("invalid date")
}

func normalizeABHA(v string) string {
	var b strings.Builder
	for _, c := range strings.TrimSpace(v) {
		if c >= '0' && c <= '9' {
			b.WriteRune(c)
		}
	}
	return b.String()
}

func isValidABHA(v string) bool {
	return regexp.MustCompile(`^\d{14}$`).MatchString(strings.TrimSpace(v))
}

func isAllowedGender(v string) bool {
	switch strings.ToLower(strings.TrimSpace(v)) {
	case "male", "female", "other", "unknown":
		return true
	default:
		return false
	}
}

func normalizeIndianPhone(raw string) (string, error) {
	s := strings.TrimSpace(raw)
	if s == "" {
		return "", fmt.Errorf("phone_number is required")
	}
	s = strings.Map(func(r rune) rune {
		switch {
		case r >= '0' && r <= '9':
			return r
		case r == '+':
			return r
		default:
			return -1
		}
	}, s)

	if strings.HasPrefix(s, "+91") {
		digits := strings.TrimPrefix(s, "+91")
		if len(digits) == 10 {
			return "+91" + digits, nil
		}
	}
	if strings.HasPrefix(s, "91") && len(s) == 12 {
		return "+" + s, nil
	}
	if strings.HasPrefix(s, "0") && len(s) == 11 {
		return "+91" + strings.TrimPrefix(s, "0"), nil
	}
	if len(s) == 10 {
		return "+91" + s, nil
	}
	return "", fmt.Errorf("phone_number must be a valid Indian mobile number")
}

func maskABHA(v string) string {
	s := normalizeABHA(v)
	if len(s) < 4 {
		return ""
	}
	return strings.Repeat("*", len(s)-4) + s[len(s)-4:]
}

func maskPhone(v string) string {
	s := strings.Map(func(r rune) rune {
		if r >= '0' && r <= '9' {
			return r
		}
		return -1
	}, strings.TrimSpace(v))
	if len(s) < 4 {
		return ""
	}
	return "+**" + strings.Repeat("*", len(s)-4) + s[len(s)-4:]
}

func maskEmail(v string) string {
	parts := strings.Split(strings.TrimSpace(v), "@")
	if len(parts) != 2 || parts[0] == "" {
		return ""
	}
	prefix := parts[0]
	if len(prefix) <= 2 {
		return prefix[:1] + "***@" + parts[1]
	}
	return prefix[:2] + strings.Repeat("*", len(prefix)-2) + "@" + parts[1]
}

func (h *Handler) resolveViewerRef(ctx context.Context, cognitoSub string) string {
	resolveCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	userID, err := h.resolveASHAUserID(resolveCtx, cognitoSub)
	if err != nil || strings.TrimSpace(userID) == "" {
		return cognitoSub
	}
	return userID
}

func (h *Handler) resolveViewer(ctx context.Context, cognitoSub string) (string, *string) {
	viewerRef := h.resolveViewerRef(ctx, cognitoSub)
	if looksLikeUUID(viewerRef) {
		return viewerRef, &viewerRef
	}
	return viewerRef, nil
}

func parseAgeFromDOB(dateOfBirth string) int {
	if strings.TrimSpace(dateOfBirth) == "" {
		return 0
	}
	dob, err := time.Parse("2006-01-02", strings.TrimSpace(dateOfBirth))
	if err != nil {
		return 0
	}
	now := time.Now().UTC()
	age := now.Year() - dob.Year()
	if now.Month() < dob.Month() || (now.Month() == dob.Month() && now.Day() < dob.Day()) {
		age--
	}
	if age < 0 {
		return 0
	}
	return age
}
