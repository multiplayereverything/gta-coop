#pragma once
class CNetworkPed
{
private:
	CNetworkPed() {}
public:
	pedid_t m_pedId{};
	CPed* m_pPed = nullptr;
	bool m_bSyncing = false;
	ePedType m_nPedType;
	unsigned char m_nCreatedBy;
	CVector m_vecVelocity{0.0f, 0.0f, 0.0f};
	float m_fAimingRotation = 0.0f;
	float m_fCurrentRotation = 0.0f;
	float m_fLookDirection = 0.0f;
	eMoveState m_nMoveState = eMoveState::PEDMOVE_NONE;
	float m_fMoveBlendRatio = 0.0f;
	CAutoPilot m_autoPilot;
	float m_fGasPedal = 0.0f;
	float m_fBreakPedal = 0.0f;
	float m_fSteerAngle = 0.0f;
	float m_fHealth = 100.0f;
	bool m_bClaimOnRelease = false;

	// on-foot smoothing (receiving side): last synced position, when it arrived; see CNetworkPedManager::Process
	CVector m_vecSyncedPos{0.0f, 0.0f, 0.0f};
	uint32_t m_nSyncedPosTime = 0;
	// jitter metric (tests): position and movement in the previous frame
	CVector m_vecLastFramePos{0.0f, 0.0f, 0.0f};
	CVector m_vecLastFrameStep{0.0f, 0.0f, 0.0f};
	bool m_bHasLastFrame = false;

	static CNetworkPed* CreateHosted(CPed* ped);
	void WarpIntoVehicleDriver(CVehicle* vehicle);
	void WarpIntoVehiclePassenger(CVehicle* vehicle, int seatid);
	void RemoveFromVehicle(CVehicle* vehicle);
	void ClaimOnRelease();
	void CancelClaim();

	void ApplyWeaponSnapshot(Packets::Players::SWeaponSnapshot& weaponSnapshot);

	CNetworkPed(pedid_t pedid, int modelId, ePedType pedType, CVector pos, unsigned char createdBy, char specialModelName[]);
	~CNetworkPed();
};

