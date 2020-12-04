#lang typed/racket/base

(provide (all-defined-out))
(provide (all-from-out typed/racket/date))

(require typed/racket/date)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
(define msdos-datetime->utc-seconds : (->* (Index Index) (Boolean) Natural)
  ; https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-dosdatetimetofiletime?redirectedfrom=MSDN
  (lambda [msdos-date msdos-time [locale? #false]]
    (define year (+ (bitwise-bit-field msdos-date 9 16) 1980))
    (define month (bitwise-bit-field msdos-date 5 9))
    (define day (bitwise-bit-field msdos-date 0 5))
    (define hour (bitwise-bit-field msdos-time 11 16))
    (define minute (bitwise-bit-field msdos-time 5 11))
    (define second (* (bitwise-bit-field msdos-time 0 5) 2))

    (assert (find-seconds second minute hour day month year locale?) exact-nonnegative-integer?)))

(define utc-seconds->msdos-datetime : (->* (Integer) (Boolean) (Values Index Index))
  ; https://docs.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-dosdatetimetofiletime?redirectedfrom=MSDN
  (lambda [utc-seconds [locale? #false]]
    (define the-date (seconds->date utc-seconds locale?))
    (define msdos-date : Natural
      (bitwise-ior (date-day the-date)
                   (arithmetic-shift (date-month the-date) 5)
                   (arithmetic-shift (max (- (date-year the-date) 1980) 0) 9)))
    (define msdos-time : Natural
      (bitwise-ior (quotient (date-second the-date) 2)
                   (arithmetic-shift (date-minute the-date) 5)
                   (arithmetic-shift (date-hour the-date) 11)))
    
    (values (assert msdos-date index?) (assert msdos-time index?))))