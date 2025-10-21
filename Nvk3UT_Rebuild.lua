Nvk3UT = Nvk3UT or {}
function Nvk3UT.RebuildSelected(ach)
    ach = ach or ACHIEVEMENTS
    if not ach or not ach.categoryTree or not ach.OnCategorySelected then return end
    if Nvk3UT._rebuild_lock then return end
    local data = ach.categoryTree:GetSelectedData()
    if not data then return end
    Nvk3UT._rebuild_lock = true
    -- call once; our overrides must NOT call RebuildSelected again
    ach:OnCategorySelected(data, true)
    Nvk3UT._rebuild_lock = false
end
