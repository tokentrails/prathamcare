package models

// HealthLake FHIR payload wrappers used by service/repository layers.

// FHIRReference references a FHIR resource, e.g. "Patient/123".
type FHIRReference struct {
	Reference string `json:"reference"`
	Display   string `json:"display,omitempty"`
}

type FHIRCoding struct {
	System  string `json:"system,omitempty"`
	Code    string `json:"code,omitempty"`
	Display string `json:"display,omitempty"`
}

type FHIRCodeableConcept struct {
	Coding []FHIRCoding `json:"coding,omitempty"`
	Text   string       `json:"text,omitempty"`
}

type FHIRHumanName struct {
	Text   string   `json:"text,omitempty"`
	Family string   `json:"family,omitempty"`
	Given  []string `json:"given,omitempty"`
}

type FHIRPatientResource struct {
	ResourceType string          `json:"resourceType"`
	ID           string          `json:"id,omitempty"`
	Identifier   []map[string]any `json:"identifier,omitempty"`
	Name         []FHIRHumanName `json:"name,omitempty"`
	Gender       string          `json:"gender,omitempty"`
	BirthDate    string          `json:"birthDate,omitempty"`
}

type FHIREncounterResource struct {
	ResourceType string              `json:"resourceType"`
	ID           string              `json:"id,omitempty"`
	Status       string              `json:"status"`
	Class        map[string]any      `json:"class,omitempty"`
	Subject      *FHIRReference      `json:"subject,omitempty"`
	Participant  []map[string]any    `json:"participant,omitempty"`
	Period       map[string]string   `json:"period,omitempty"`
	ReasonCode   []FHIRCodeableConcept `json:"reasonCode,omitempty"`
}

type FHIRObservationResource struct {
	ResourceType          string               `json:"resourceType"`
	ID                    string               `json:"id,omitempty"`
	Status                string               `json:"status"`
	Code                  FHIRCodeableConcept  `json:"code"`
	Subject               *FHIRReference       `json:"subject,omitempty"`
	Encounter             *FHIRReference       `json:"encounter,omitempty"`
	EffectiveDateTime     string               `json:"effectiveDateTime,omitempty"`
	ValueQuantity         map[string]any       `json:"valueQuantity,omitempty"`
	ValueString           string               `json:"valueString,omitempty"`
}
