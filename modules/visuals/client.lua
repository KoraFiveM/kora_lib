

function QB.visuals.fade(coords, duration)
    if not duration then duration = 500 end
    DoScreenFadeOut(duration)
    while not IsScreenFadedOut() do
        Wait(10)
    end
    if coords then
        SetEntityCoords(PlayerPedId(), coords.x, coords.y, coords.z)
    end
    DoScreenFadeIn(duration)
end