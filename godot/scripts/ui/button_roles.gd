class_name ButtonRoles
extends RefCounted

## Gives every named button its role's look (see the button-role styles in
## `theme/ardenia_theme.tres`). One table, so a new button joins a role by
## adding its name here rather than by editing scenes one by one. Unlisted
## buttons — speed pips, list entries, pickers — keep the plain style.

const ROLES := {
	"NavButton": ["BudgetButton", "LegislationButton", "DiplomacyButton", "RecordsButton"],
	"PrimaryButton": ["PlayButton", "NextDecision", "RegionAction", "ProposeBudgetButton",
		"VoteBudgetButton", "ProposeBillButton", "VoteBillButton", "SupportButton",
		"AddPledgeButton", "AppointShadowButton", "OppositionCampaignButton",
		"CampaignButton1", "CampaignButton2", "CampaignButton3",
		"ContinueButton", "NewCampaignButton"],
	"DangerButton": ["WithdrawBudgetButton", "WithdrawBillButton", "OpposeButton",
		"DropButton1", "DropButton2", "DropButton3", "QuitButton"],
	"QuietButton": ["SaveButton", "LoadButton", "OptionsButton", "CloseBudgetButton",
		"CloseLegislationButton", "CloseDiplomacyButton", "CloseRecordsButton",
		"CloseOppositionButton", "CloseSituationButton", "CloseRegionButton"],
}


static func role_of(button_name: String) -> String:
	for role in ROLES:
		if button_name in ROLES[role]:
			return role
	return ""


static func apply(root: Node) -> void:
	for node in root.find_children("*", "Button", true, false):
		var role := role_of(String(node.name))
		if role != "":
			(node as Button).theme_type_variation = role
