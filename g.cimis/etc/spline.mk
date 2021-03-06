#! /usr/bin/make -f

ifndef configure.mk
include configure.mk
endif

V.info:=@
spline.mk:=1

# Lapse Rates/Tensions/Smooth for dewp and min_at
T_tension:=10
T_smooth:=0.03
lr-day_dew_pnt:=5
lr-day_air_tmp_min:=5
lr-day_air_tmp_max:=5
lr-day_wind_spd_avg:=0
lr-day_rel_hum_max:=0

# Generic vol.rst parmeters
tension:=5
zmult:=30
smooth:=0.05
tzs:=t${tension}_z$(zmult)_s$(smooth)

calc=r.mapcalc --overwrite --quiet expression="$1=$(subst ",\",$2)"

.PHONY: info
info::
	@echo spline.mk
	@echo

###############################################################
# Generic/Simple s.vol.rst interpolations
# These are used to calculate
# d_max_rh and d_avg_ws
# These show the input parameters in the name so that we can keep
# a few around.  Mostly, they're used in combination of other rasters anyways
###############################################################
define spline_template
clean::
	g.remove $(1)_t$(2)_z$(3)_s$(4)

$(rast)/$(1)_t$(2)_z$(3)_s$(4): ${vect}/et
	${V.info}g.region -d; \
	v.vol.rst --quiet --overwrite segmax=700 npmin=100 \
	  input=et wcolumn=${1} cross_input=${Z} \
	  maskmap=${state} where="${1}_qc in ('K','Y','H','')" \
	  tension=$(2) zscale=$(3) smooth=$(4) \
	  cross_output=$(1)_t$(2)_z$(3)_s$(4) 2> /dev/null
endef

$(foreach p,day_rel_hum_max day_wind_spd_avg,$(eval $(call spline_template,$(p),$(tension),$(zmult),$(smooth))))

#####################################################################
# These rules build temperature lapse-rate normalized, rasters
# Using 2-d splines to fit the normalized data
#
# The output is a raster $(name)_ns to indicate normalized splines
# intermediate files include: normalized site_list,normalized_spline
#####################################################################
clean::
	g.remove vect=z_normal

$(eval $(call grass_vect_shorthand,z_normal))

${vect}/z_normal:${vect}/et
	g.copy --o vect=et,z_normal
	echo 'update z_normal set day_air_tmp_min=day_air_tmp_min+${lr-day_air_tmp_min}*z/1000,day_air_tmp_max=day_air_tmp_max+${lr-day_air_tmp_max}*z/1000,day_wind_spd_avg=day_wind_spd_avg+${lr-day_wind_spd_avg}*z/1000,day_rel_hum_max=day_rel_hum_max+${lr-day_rel_hum_max}*z/1000,day_dew_pnt=day_dew_pnt+${lr-day_dew_pnt}*z/1000;' | ${SQLITE} ${db.connect.database}
	v.support map_name="Normalized CIMIS Station parameters" map=z_normal

define normalized_T
#.PHONY: $(1)_ns
#$(1)_ns: $(rast)/$(1)_ns
clean::
	g.remove rast=z_$(1)_lr$(2)_t$(3)_s$(4),$(1)_ns

# ...  maskmap=MASK
# Normalized Spline for Lapse Rate Calculation
$(rast)/z_$(1)_lr$(2)_t$(3)_s$(4): ${vect}/z_normal
	$(call NOMASK)
	v.surf.rst --overwrite npmin=100 segmax=200 input=z_normal \
	  zcolumn=${1} where="${1}_qc in ('K','Y','H','')" \
	  tension=$(3) smooth=$(4) \
	  elev=$$(notdir $$@)

# ReUnNormalized back to Elevation
$(rast)/$(1)_ns: $(rast)/z_$(1)_lr$(2)_t$(3)_s$(4)
	$(call NOMASK)\
	$(call calc,$(1)_ns,z_$(1)_lr$(2)_t$(3)_s$(4)-$(2)*Z@2km/1000)

endef

ns-vars:=day_air_tmp_min day_air_tmp_max day_dew_pnt
$(foreach p,${ns-vars},$(eval $(call normalized_T,${p},${lr-${p}},$(T_tension),$(T_smooth))))
