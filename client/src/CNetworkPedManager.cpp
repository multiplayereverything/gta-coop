#include "stdafx.h"
#include "CNetworkVehicle.h"
#include "CNetworkPed.h"
#include "CAutoTest.h"

std::vector<CNetworkPed*> CNetworkPedManager::m_pPeds;

CNetworkPed* CNetworkPedManager::GetPed(pedid_t pedid)
{
    if (!pedid.valid())
        return nullptr;

    for (int i = 0; i != m_pPeds.size(); i++)
    {
        if (m_pPeds[i]->m_pedId == pedid)
        {
            return m_pPeds[i];
        }
    }
    return nullptr;
}

CNetworkPed* CNetworkPedManager::GetPed(CEntity* entity)
{
    if (entity == nullptr)
        return nullptr;

    for (int i = 0; i != m_pPeds.size(); i++)
    {
        if (m_pPeds[i]->m_pPed == entity)
        {
            return m_pPeds[i];
        }
    }

    return nullptr;
}

void CNetworkPedManager::Add(CNetworkPed* ped)
{
    CNetworkPedManager::m_pPeds.push_back(ped);
}

void CNetworkPedManager::Remove(CNetworkPed* ped)
{
    auto it = std::find(m_pPeds.begin(), m_pPeds.end(), ped);
    if (it != m_pPeds.end())
    {
        m_pPeds.erase(it);
    }
}

void CNetworkPedManager::Update()
{
    CNetworkPedManager::RemoveHostedUnused();

    for (CNetworkPed* pNetworkPed : m_pPeds)
    {
        if (!pNetworkPed->m_bSyncing)
            continue;

        CPed* pPed = pNetworkPed->m_pPed;
        if (!pPed)
            continue;

        CVehicle* pVehicle = pPed->m_pVehicle;
        CNetworkVehicle* pNetworkVehicle = pVehicle ? CNetworkVehicleManager::GetVehicle(pVehicle) : nullptr;

        if (pNetworkVehicle && pPed->m_nPedFlags.bInVehicle)
        {
            bool isDriver = (pVehicle->m_pDriver == pPed);

            if (isDriver)
            {
                Packets::Peds::PedDriverUpdate packet{};

                packet.vehicleSubType = static_cast<eVehicleType>(pVehicle->m_nVehicleSubType);

                packet.pedid = pNetworkPed->m_pedId;
                packet.vehicleid = pNetworkVehicle->m_vehicleId;

                packet.pos = pVehicle->m_matrix->pos;
                packet.roll = pVehicle->m_matrix->right;
                packet.rot = pVehicle->m_matrix->up;
                packet.velocity = pVehicle->m_vecMoveSpeed;
                packet.turnSpeed = pVehicle->m_vecTurnSpeed;

                packet.pedHealth.iHealth = static_cast<uint8_t>(std::clamp(pPed->m_fHealth, 0.0f, 255.0f));
                packet.pedHealth.iArmour = static_cast<uint8_t>(std::clamp(pPed->m_fArmour, 0.0f, 255.0f));

                CWeapon& weapon = pPed->GetWeapon();
                packet.pedWeapon.iWeaponType = weapon.m_eWeaponType;
                packet.pedWeapon.iWeaponState = weapon.m_nState;
                packet.pedWeapon.nAmmo = weapon.m_nAmmoInClip;

                packet.color1 = pVehicle->m_nPrimaryColor;
                packet.color2 = pVehicle->m_nSecondaryColor;

                packet.health = pVehicle->m_fHealth;

                packet.paintjob = pVehicle->GetRemapIndex();

                if (pVehicle->m_nVehicleType == VEHICLE_BIKE)
                {
                    CBike* pBike = (CBike*)pVehicle;
                    packet.bikeLean = pBike->m_rideAnimData.m_fDesiredLeanAngle;
                }
                if (pVehicle->m_nVehicleSubType == VEHICLE_PLANE)
                {
                    CPlane* pPlane = (CPlane*)pVehicle;
                    packet.planeGearState = pPlane->m_fLandingGearStatus;
                }
                if (pVehicle->m_nVehicleSubType == eVehicleType::VEHICLE_BMX)
                {
                    CBmx* pBmx = (CBmx*)pVehicle;
                    packet.controlPedaling = pBmx->m_fControlPedaling;
                }
                if (pVehicle->m_nVehicleType == VEHICLE_AUTOMOBILE)
                {
                    CAutomobile* pAutomobile = (CAutomobile*)pVehicle;
                    packet.bikeLean = pAutomobile->m_wMiscComponentAngle;
                }
                packet.locked = pVehicle->m_eDoorLock;
                packet.gasPedal = pVehicle->m_fGasPedal;
                packet.breakPedal = pVehicle->m_fBreakPedal;
                packet.steerAngle = pVehicle->m_fSteerAngle;

                GetPacketFactory().Send(packet);
            }
            else
            {
                Packets::Peds::PedPassengerSync packet{};
                packet.pedid = pNetworkPed->m_pedId;
                packet.vehicleid = pNetworkVehicle->m_vehicleId;

                packet.healthSnapshot.iHealth = static_cast<uint8_t>(std::clamp(pPed->m_fHealth, 0.0f, 255.0f));
                packet.healthSnapshot.iArmour = static_cast<uint8_t>(std::clamp(pPed->m_fArmour, 0.0f, 255.0f));

                CWeapon& weapon = pPed->GetWeapon();
                packet.weaponSnapshot.iWeaponType = weapon.m_eWeaponType;
                packet.weaponSnapshot.iWeaponState = weapon.m_nState;
                packet.weaponSnapshot.nAmmo = weapon.m_nAmmoInClip;

                for (int i = 0; i < pNetworkVehicle->m_pVehicle->m_nMaxPassengers; i++)
                {
                    if (pNetworkVehicle->m_pVehicle->m_apPassengers[i] == pNetworkPed->m_pPed)
                    {
                        packet.seatid = i;
                        break;
                    }
                }
                GetPacketFactory().Send(packet);
            }
        }
        else
        {
            Packets::Peds::PedOnFoot packet{};

            packet.pedid = pNetworkPed->m_pedId;
            packet.pos = pPed->m_matrix->pos;
            packet.velocity = pPed->m_vecMoveSpeed;

            packet.healthSnapshot.iHealth = static_cast<uint8_t>(std::clamp(pPed->m_fHealth, 0.0f, 255.0f));
            packet.healthSnapshot.iArmour = static_cast<uint8_t>(std::clamp(pPed->m_fArmour, 0.0f, 255.0f));

            CWeapon& weapon = pPed->GetWeapon();
            packet.weaponSnapshot.iWeaponType = weapon.m_eWeaponType;
            packet.weaponSnapshot.iWeaponState = weapon.m_nState;
            packet.weaponSnapshot.nAmmo = weapon.m_nAmmoInClip;

            packet.aimingRotation = pPed->m_fAimingRotation;
            packet.currentRotation = pPed->m_fCurrentRotation;
            packet.lookDirection = pPed->m_fLookDirection;
            packet.moveState = (eMoveState)pPed->m_nMoveState;

            packet.bDucked = CUtil::IsDucked(pPed);

            CTaskSimpleUseGun* useGun = pPed->m_pIntelligence->GetTaskUseGun();

            if (useGun)
            {
                packet.bAiming = true;
                packet.weaponAim = useGun->m_pTarget && (useGun->m_vecTarget.x == 0.f || useGun->m_vecTarget.y == 0.f)
                                       ? useGun->m_pTarget->GetPosition()
                                       : useGun->m_vecTarget;
            }

            packet.fightingStyle = pPed->m_nFightingStyle;

            GetPacketFactory().Send(packet);
        }
    }
}

// jitter metric for tests: how much a ped's frame-to-frame movement changes (smooth walking is low, snapping spikes)
static void MeasureJitter(CNetworkPed* networkPed, double& sum, uint32_t& samples)
{
    CPed* ped = networkPed->m_pPed;
    if (!CAutoTest::ms_bEnabled || !ped || !ped->m_matrix || ped->m_nPedFlags.bInVehicle)
        return;
    // counts reversals: a moving ped (>1 cm/frame both frames, horizontally) stepping backwards against its previous
    // step - walking almost never does that, a snap back to a synced position always does. sum = reversals x 100
    CVector step = ped->GetPosition() - networkPed->m_vecLastFramePos;
    if (networkPed->m_bHasLastFrame && step.Magnitude() < 3.0f)
    {
        CVector2D now(step.x, step.y), before(networkPed->m_vecLastFrameStep.x, networkPed->m_vecLastFrameStep.y);
        if (now.Magnitude() > 0.01f && before.Magnitude() > 0.01f)
        {
            if (now.x * before.x + now.y * before.y < 0.0f)
                sum += 100.0;
            samples++;
        }
    }
    networkPed->m_vecLastFrameStep = networkPed->m_bHasLastFrame ? step : CVector(0.0f, 0.0f, 0.0f);
    networkPed->m_vecLastFramePos = ped->GetPosition();
    networkPed->m_bHasLastFrame = true;
}

void CNetworkPedManager::Process()
{
    for (auto networkPed : m_pPeds)
    {
        if (networkPed->m_bSyncing)
        {
            MeasureJitter(networkPed, ms_fOwnJitterSum, ms_nOwnJitterSamples);  // baseline: peds this game runs
            continue;
        }

        CPed* ped = networkPed->m_pPed;

        if (ped == nullptr)
            continue;

        if (!ped->m_nPedFlags.bInVehicle)
        {
            ped->m_fAimingRotation = networkPed->m_fAimingRotation;
            ped->m_fCurrentRotation = networkPed->m_fCurrentRotation;
            ped->m_fLookDirection = networkPed->m_fLookDirection;

            // glide towards where the owner's ped is now: last synced position moved on by its velocity (velocity is
            // per 1/50 s; predict at most 200 ms), closing ~25% of the gap per 50 fps frame instead of snapping
            if (ms_bSmoothing && networkPed->m_nSyncedPosTime != 0 && ped->m_matrix)
            {
                uint32_t age = CTimer::m_snTimeInMilliseconds - networkPed->m_nSyncedPosTime;
                float ahead = (std::min)(age, 200u) / 20.0f;
                CVector predicted = networkPed->m_vecSyncedPos + networkPed->m_vecVelocity * ahead;
                CVector error = predicted - ped->GetPosition();
                // height is left to the local ground collision/gravity (pulling it fought them: vertical jitter),
                // unless it is clearly off (stairs, slopes the other game resolved differently)
                if (fabs(error.z) < 1.0f)
                    error.z = 0.0f;
                if (error.Magnitude() > 0.05f)
                {
                    float k = (std::min)(ms_fSmoothingStrength * CTimer::ms_fTimeStep, 1.0f);
                    ped->SetPosn(ped->GetPosition() + error * k);
                }
                ped->m_vecMoveSpeed = networkPed->m_vecVelocity;
            }

            MeasureJitter(networkPed, ms_fJitterSum, ms_nJitterSamples);
        }
    }
}

void CNetworkPedManager::AssignHost()
{
    /*for (auto networkPed : m_pPeds)
    {
        CPed* ped = networkPed->m_pPed;

        if (ped)
        {
            ped->SetCharCreatedBy(networkPed->m_nCreatedBy);

            CTaskComplexWander* task = plugin::CallAndReturn<CTaskComplexWander*, 0x673D00>(ped); //
    GetWanderTaskByPedType ped->m_pIntelligence->m_TaskMgr.SetTask(task, 0, false);
        }
    }*/
}

pedid_t CNetworkPedManager::AllocatePedId()
{
    assert(CNetworkPlayerManager::m_localPlayerId.valid());
    return pedid_t(CNetworkPlayerManager::m_localPlayerId, ms_nNextPedId++);
}

void CNetworkPedManager::ResetIdAllocator()
{
    ms_nNextPedId = 1;
}

void CNetworkPedManager::RemoveHostedUnused()
{
    for (auto it = CNetworkPedManager::m_pPeds.begin(); it != CNetworkPedManager::m_pPeds.end();)
    {
        if ((*it)->m_bSyncing)
        {
            CPed* ped = (*it)->m_pPed;
            if (!IsPedPointerValid(ped))
            {
                delete *it;
                it = m_pPeds.erase(it);
                continue;
            }
        }
        ++it;
    }
}
