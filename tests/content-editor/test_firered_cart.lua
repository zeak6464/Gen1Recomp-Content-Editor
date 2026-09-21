return function(root)
 local C,IO=require("Cartkit"),require("ModIO")
 local dir=root.."/tests/content-editor/cart-check/firered_cart_check"
 local S={dataPrefs={recompRoot=os.getenv("POKEPORT_RECOMP")}}
 if not IO.readText(dir.."/cart.json") then
  local ok,out=C.run(S,{"scaffold","firered_cart_check","--base","firered","--into",root.."/tests/content-editor/cart-check"});assert(ok,out)
 end
 local cart=assert(C.readCart(dir));assert(cart.base=="firered")
 cart.mods={{id="firered_cart_test",source="local",version="1.0.0"}}
 cart.load_order={"firered_cart_test"}
 local path=dir.."/firered-test.g1rcart"
 assert(C.packBundle(dir,cart,path))
 local parsed=assert(require("src.carts.CartManifest").decode(assert(IO.readText(path))))
 assert(parsed.base=="firered" and parsed.mods[1].id=="firered_cart_test")
 local ok,out=C.run(S,{"validate",dir});assert(ok,out)
end
