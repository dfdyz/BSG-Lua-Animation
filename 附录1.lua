--=====================Animation Lib===============================
--声明
Internal = { }
Internal.machines = {}
Internal.TPS = 60
SetTPS = function(t)
  Internal.TPS = t
  return Internal.TPS
end
AddAnimMachine = function(M)
  table.insert(Internal.machines,M)
end

function Internal.DeepCopy(obj)
  local InTable = {};
  local function Func(obj)
    if type(obj) ~= "table" then   --判断表中是否有表
      return obj;
    end
    local NewTable = {};  --定义一个新表
    InTable[obj] = NewTable;  --若表中有表，则先把表给InTable，再用NewTable去接收内嵌的表
    for k,v in pairs(obj) do  --把旧表的key和Value赋给新表
      NewTable[Func(k)] = Func(v);
    end
    return setmetatable(NewTable, getmetatable(obj))--赋值元表
  end
  return Func(obj) --若表中有表，则把内嵌的表也复制了
end

function Log(v)
  if DeBug_Mode then
    print(v)
  end
end

function Note_new(name)
  t = {}
  t.ang = 0
  t.name = name
  t.ref = machine.get_refs_control(name)
  return t
end

function Note_update(note)
  note.ref.set_steering(note.ang)
end

function Anim_Machine_new(layer_count)
  layer_count = layer_count or 1
  t = {}
  t.notes = {}
  t.layer = {}
  for i = 1, layer_count do
    t.layer[i] = {}
  end
  return t
end

function Anim_Machine_AddNote(m,n)
  m.notes[n.name] = n
end

function Anim_Machine_ChangeAnim(m,l,a,turn_tick)     --Anim_Machine_ChangeAnim(Anim_Machine Machine,int layer,Anim animation[,int turn_tick]);  return Anim;
  local t = Internal.DeepCopy(a)
  turn_tick = turn_tick or 0
  t.turn_tick,t.max_turn_tick = turn_tick,turn_tick
  t.tag = false
  table.insert(m.layer[l],t)
  return t
end

function Anim_Machine_Clear(m)
  for _, n in pairs(m.notes) do
    n.ang = 0
  end
end

Arc = { line = function(t) return t end,

}--预设曲线

--[[
关键帧示例
Key = { notes = { ["Note1"] = 90 } ,  Note1骨骼   旋转至90°
        arc = Arc.line  --平滑曲线函数 类型function
}

]]--

--Anim = { keys = {} , tick = 0 , alpha = 0 , turn_tick = 0 , max_turn_tick = 0 , loop = false , tag = false}

function Anim_new(keys)
  local t = {}
  keys = keys or {}
  t.keys = keys
  t.tick = 0
  t.alpha = 0
  t.max_turn_tick = 0
  t.loop = false
  t.turn_tick = 0
  t.tag = false
  return t
end

function Anim_Copy(anim)
  local t = {}
  t.keys = anim.keys
  t.tick = anim.tick
  t.alpha = anim.alpha
  t.max_turn_tick = anim.max_turn_tick
  t.loop = anim.loop
  t.turn_tick = anim.turn_tick
  t.tag = anim.tag
  return t
end

function Anim_getMaxTick(anim)
  local t = 0
  for k,_ in pairs(anim.keys) do
    if k > t then
      t = k
    end
  end
  return t
end

function getTableMaxKey(t)
  local tmp = 0
  for k,_ in pairs(t) do
    if k > tmp then
      tmp = k
    end
  end
  return tmp
end

Internal.Update_All_Animation = function()
  local d_time = time.delta_time()
  local d_tick = d_time * Internal.TPS
  --print(d_tick)


  for j,m in pairs(Internal.machines) do
    --处理动画
    Anim_Machine_Clear(m)
    local MaxLayer = getTableMaxKey(m.layer)

    for i = 1, MaxLayer do
      local Layer = m.layer[i]

      --处理层
      local tmp_tag = false
      while true do
        local max_key = getTableMaxKey(Layer)

        for i=1, max_key do
          if Layer[i].tag then
            table.remove(Layer,i)
            tmp_tag = false
            break
          end
        end
        if tmp_tag then
          break
        end
        tmp_tag = true
      end

      local count = getTableMaxKey(Layer)
      for i = 1 , count do
        local ani = Layer[i]
        local max_tick = Anim_getMaxTick(ani)
        local tmp_v = 0
        local turn_alpha = 0

        --计算tick
        ani.tick = d_tick + ani.tick
        while ani.tick >= max_tick do
          ani.tick = ani.tick - max_tick
          tmp_v = tmp_v + 1
          --及时止损
          if tmp_v > 5 then
            ani.tick = 0
            break
          end
        end

        --处理过渡tick
        if ani.max_turn_tick > 0 then
          ani.turn_tick = ani.turn_tick - d_tick
          if ani.turn_tick < 0 then
            ani.turn_tick = 0
            ani.max_turn_tick = 0
            for n = 1, i do
              if Layer[n-1] ~= nil then
                Layer[n-1].tag = true
              end
            end
          else
            turn_alpha = ani.turn_tick /ani.max_turn_tick
          end
        end

        --处理骨骼
        for name,note in pairs(m.notes) do
          local before = -1
          local after = -1
          local rt = true
          function handle_note()
            --查找前后帧
            for tick,key in pairs(ani.keys) do
              if key.notes[name] ~= nil then
                if tick <= ani.tick and tick > before then
                  before = tick
                end
              end
            end

            if before == -1 then
              return
            end

            after = before

            for tick,key in pairs(ani.keys) do
              if key.notes[name] ~= nil and tick > after then
                after = tick
              end
            end

            for tick,key in pairs(ani.keys) do
              if key.notes[name] ~= nil then
                if tick > before and tick < after then
                  after = tick
                end
              end
            end

            --更新骨骼

            local t = ( ani.tick - before ) / ( after - before )
            t = ani.keys[after].arc(t)
            local after_ang = ani.keys[after].notes[name]
            local before_ang = ani.keys[before].notes[name]

            local tmp_ang = (after_ang-before_ang) * t + before_ang

            --处理层透明度
            if ani.max_turn_tick > 0 then
              tmp_ang = note.ang * ani.alpha + tmp_ang * (1 - ani.alpha)
              note.ang = note.ang * turn_alpha + tmp_ang * (1 - turn_alpha)
            else
              note.ang = note.ang * ani.alpha + tmp_ang * (1 - ani.alpha)
            end
          end

          handle_note()
          Note_update(note)
        end
      end
    end
  end
end
