#define PERL_NO_GET_CONTEXT
#include <EXTERN.h>
#include <perl.h>
#include <XSUB.h>

#ifdef USE_PPPORT
#include "ppport.h"
#endif

#define NSC_setsv_to_gv(gv, sv) sv_setsv_mg((SV*)(gv), sv_2mortal(newRV_inc((SV*)(sv))))

#define NSC_STORAGE_VAR "__NAMESPACE_CLEAN_STORAGE"

static int nsc_on_scope_end(pTHX_ SV* const sv, MAGIC* const mg);

static MGVTBL nsc_magic_vtbl = {
    NULL, /* get */
    NULL, /* set */
    NULL, /* len */
    NULL, /* clear */
    nsc_on_scope_end, /* free */
    NULL, /* copy */
    NULL, /* dup */
#ifdef MGf_LOCAL
    NULL,  /* local */
#endif
};

#define hv_has_true_value_pvn(hv, k, l) nsc_hv_has_true_value_pvn(aTHX_ (hv), (k), (l))
#define hv_has_true_value_pvs(hv, s)    nsc_hv_has_true_value_pvn(aTHX_ (hv), STR_WITH_LEN(s))
#define hv_has_true_value_sv(hv, sv)    nsc_hv_has_true_value_sv(aTHX_ (hv), (sv))

static int
nsc_hv_has_true_value_pvn(pTHX_ HV* const hv, const char* const key, I32 const keylen){
    SV** const svp = hv_fetch(hv, key, keylen, FALSE);
    return svp && SvTRUE(*svp);
}

static int
nsc_hv_has_true_value_sv(pTHX_ HV* const hv, SV* const keysv){
    HE* const he = hv_fetch_ent(hv, keysv, FALSE, 0U);
    if(he){
        SV* const value = hv_iterval(hv, he);
        return SvTRUE(value);
    }
    return FALSE;
}

static void
nsc_remove_sub(pTHX_ HV* const cleanee, SV* const name){
    GV* gv;

    assert(cleanee);
    assert(SvTYPE(cleanee) == SVt_PVHV);

    assert(name);

    ENTER;
    SAVETMPS;

    gv = (GV*)hv_delete_ent(cleanee, name, 0x00, 0U);
    if(gv && isGV(gv)
        && ( GvSV(gv) || GvAV(gv) || GvHV(gv) || GvIO(gv) || GvFORM(gv) )){

        STRLEN namelen;
        const char* const namepv = SvPV_const(name, namelen);
        GV* const newgv = (GV*)*hv_fetch(cleanee, namepv, namelen, TRUE);

        gv_init(newgv, cleanee, namepv, namelen, GV_ADDMULTI);

        if(GvSV(gv))   NSC_setsv_to_gv(newgv, GvSV(gv));
        if(GvAV(gv))   NSC_setsv_to_gv(newgv, GvAV(gv));
        if(GvHV(gv))   NSC_setsv_to_gv(newgv, GvHV(gv));
        if(GvIO(gv))   NSC_setsv_to_gv(newgv, GvIOp(gv));
        if(GvFORM(gv)) NSC_setsv_to_gv(newgv, GvFORM(gv));

    }

    FREETMPS;
    LEAVE;
}

static void
nsc_get_functions(pTHX_ const char* const package, HV* const exclude, HV* const output){
    HV* const stash = gv_stashpv(package, TRUE);
    HE* he;

    hv_iterinit(stash);
    while((he = hv_iternext(stash))){
        SV* const keysv = hv_iterkeysv(he);
        GV* const gv    = (GV*)hv_iterval(stash, he);

        if( (!isGV(gv) || GvCVu(gv)) /* has a CODE slot */
            && !(exclude && hv_has_true_value_sv(exclude, keysv)) /* not excluded */
            && !hv_exists_ent(output, keysv, 0U) ){ 

            hv_store_ent(output, keysv, newRV_inc((SV*)gv), 0U);
        }
    }
}

/* $Storage{$package} ||= {} } */
static HV*
nsc_get_class_metadata(pTHX_ const char* const package){
    const char* const fq_name = Perl_form(aTHX_ "%s::" NSC_STORAGE_VAR, package);
    return get_hv(fq_name, GV_ADDMULTI);
}

static HV*
nsc_get_registered_funcs(pTHX_ HV* const meta){
    SV** const svp = hv_fetchs(meta, "remove", FALSE);
    HV* funcs;

    if(!svp){
        funcs = newHV();
        hv_stores(meta, "remove", newRV_noinc((SV*)funcs));
    }
    else{
        assert(SvROK(*svp));
        assert(SvTYPE(SvRV(*svp)) == SVt_PVHV);
        funcs = (HV*)SvRV(*svp);
    }
    return funcs;
}

static void
nsc_register_scope_end_hook(pTHX_ const char* const cleanee, HV* const funcs){
    sv_magicext(
        (SV*)GvHVn(PL_hintgv), /* %^H */
        (SV*)funcs,
        PERL_MAGIC_ext,
        &nsc_magic_vtbl,
        cleanee,
        strlen(cleanee)
    );

    PL_hints |= HINT_LOCALIZE_HH;
}

static int
nsc_on_scope_end(pTHX_ SV* const sv, MAGIC* const mg){
    HV* const stash = gv_stashpvn(mg->mg_ptr, mg->mg_len, TRUE);
    HV* const funcs = (HV*)mg->mg_obj;
    HE* he;

    hv_iterinit(funcs);
    while((he = hv_iternext(funcs))){
        SV* const value = hv_iterval(funcs, he);

        if(SvTRUE(value)){
            nsc_remove_sub(aTHX_ stash, hv_iterkeysv(he));
        }
    }

    PERL_UNUSED_ARG(sv);
    return 0;
}


MODULE = namespace::clean    PACKAGE = namespace::clean

PROTOTYPES: DISABLE

void
import(klass, ...)
CODE:
{
    const char* cleanee = CopSTASHPV(PL_curcop);
    HV* meta            = NULL;
    HV* funcs           = NULL;
    HV* explicit        = NULL;
    I32 i;

    for(i = 1; i < items; i++){
        SV* const arg        = ST(i);
        const char* const pv = SvPV_nolen_const(arg);

        if(strEQ(pv, "-cleanee")){
            if(++i == items){
                croak("You must pass a package name to -cleanee");
            }
            cleanee = SvPVx_nolen_const(ST(i));

            meta  = nsc_get_class_metadata(aTHX_ cleanee);
            funcs = nsc_get_registered_funcs(aTHX_ meta);
        }
        else if(strEQ(pv, "-except")){
            SV* value;
            if(++i == items){
                croak("You must pass a function name to -except");
            }

            if(!meta){
                meta  = nsc_get_class_metadata(aTHX_ cleanee);
                funcs = nsc_get_registered_funcs(aTHX_ meta);
            }

            value = ST(i);
            if(SvROK(value) && SvTYPE(SvRV(value)) == SVt_PVAV){
                AV* const except = (AV*)SvRV(value);
                I32 const len    = av_len(except) + 1;
                I32 j;
                for(j = 0; j < len; j++){
                    hv_store_ent(funcs, *av_fetch(except, j, TRUE), newSV(0), 0U);
                }
            }
            else {
                hv_store_ent(funcs, value, newSV(0), 0U);
            }
        }
        else if(pv[0] == '-'){
            croak("Unrecognized option '%s' passed to namespace::clean->import", pv);
        }
        else { /* explicit function list */
            if(!explicit){
                explicit = newHV();
                sv_2mortal((SV*)explicit);
            }

            hv_store_ent(explicit, arg, newSViv(TRUE), 0U);
        }
    }

    if(explicit){
        nsc_register_scope_end_hook(aTHX_ cleanee, explicit);
    }
    else{
        if(!meta){
            meta  = nsc_get_class_metadata(aTHX_ cleanee);
            funcs = nsc_get_registered_funcs(aTHX_ meta);
        }
        nsc_get_functions(aTHX_ cleanee, NULL, funcs);

        if(!hv_has_true_value_pvs(meta, "handler_is_installed")){
            nsc_register_scope_end_hook(aTHX_ cleanee, funcs);
            hv_stores(meta, "handler_is_installed", newSViv(TRUE));
        }
    }
}

void
unimport(klass, ...)
CODE:
{
    const char* cleanee = CopSTASHPV(PL_curcop);
    I32 excludes        = 0;
    HV* const exclude   = newHV();
    HV* meta;
    HV* funcs;
    I32 i;
    HE* he;

    sv_2mortal((SV*)exclude);

    for(i = 1; i < items; i++){
        SV* const arg        = ST(i);
        const char* const pv = SvPV_nolen_const(arg);

        if(strEQ(pv, "-cleanee")){
            if(++i == items){
                croak("You must pass a function name to -cleanee");
            }
            cleanee = SvPVx_nolen_const(ST(i));
        }
        else if(pv[0] == '-'){
            croak("Unrecognized option '%s' passed to namespace::clean->unimport", pv);
        }
        else{
            hv_store_ent(exclude, arg, newSViv(1), 0U);
            excludes++;
        }
    }

    meta  = nsc_get_class_metadata(aTHX_ cleanee);
    funcs = nsc_get_registered_funcs(aTHX_ meta);

    if(excludes == 0){
        nsc_get_functions(aTHX_ cleanee, funcs, exclude /* output */);
    }

    hv_iterinit(exclude);
    while((he = hv_iternext(exclude))){
        /* mark it as excluded */
        hv_store_ent(funcs, hv_iterkeysv(he), newSV(0), 0U);
    }
}


void
clean_subroutines(klass, SV* cleanee, ...)
CODE:
{
    HV* const stash = gv_stashsv(cleanee, TRUE);
    I32 i;

    for(i = 2; i < items; i++){
        nsc_remove_sub(aTHX_ stash, ST(i));
    }
}

#ifdef KEEP_BACK_COMPAT

HV*
get_functions(klass, const char* package)
CODE:
{
    RETVAL = newHV();
    nsc_get_functions(aTHX_ package, NULL /* exclude */, RETVAL);
}
OUTPUT:
    RETVAL

HV*
get_class_store(klass, const char* package)
CODE:
{
    RETVAL = nsc_get_class_metadata(aTHX_ package);
    SvREFCNT_inc_simple_void_NN(RETVAL);
}
OUTPUT:
    RETVAL

#endif
