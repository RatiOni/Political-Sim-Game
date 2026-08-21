from dataclasses import dataclass


@dataclass
class HouseholdGroupState:
    """One social group's lived economic condition inside one region."""

    id: str
    group_id: str
    region_id: str
    population_share: float
    nominal_income_index: float = 1.0
    living_cost_index: float = 1.0
    real_income_index: float = 1.0
    employment_security: float = 0.7
    service_access: float = 0.6
    hardship: float = 0.3
    confidence: float = 0.5
    last_real_income_index: float = 1.0

    def status_label(self) -> str:
        if self.hardship >= 0.68:
            return "Severe hardship"
        if self.hardship >= 0.48:
            return "Under strain"
        if self.hardship >= 0.30:
            return "Insecure"
        return "Secure"

